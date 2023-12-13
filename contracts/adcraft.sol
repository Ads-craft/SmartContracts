// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts@4.9.3/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.9.3/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts@4.9.3/security/Pausable.sol";
import "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";

contract AdCraftPlatform is
    ERC721URIStorage,
    AccessControlEnumerable,
    Pausable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Staking token (ERC20)
    IERC20 private stakingToken;

    // NFT details structure
    struct AdNFT {
        uint256 engagementScore;
        uint256 totalStake;
    }

    // Reward rate per engagement score
    uint256 public rewardRate;

    // Mapping from tokenId to AdNFT details
    mapping(uint256 => AdNFT) public adNfts;

    // Mapping from tokenId to staker to staked amount
    mapping(uint256 => mapping(address => uint256)) public stakes;

    // Events
    event AdNFTCreated(uint256 indexed tokenId, string metadataUri);
    event AdEngagementUpdated(uint256 indexed tokenId, uint256 engagementScore);
    event StakeUpdated(uint256 indexed tokenId, address indexed staker, uint256 amount);
    event RewardClaimed(uint256 indexed tokenId, address indexed staker, uint256 reward);

    constructor(
        address _stakingToken,
        uint256 _rewardRate
    ) ERC721("AdCraftNFT", "ACNFT") {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function createAdNFT(string calldata metadataUri) external onlyRole(ADMIN_ROLE) whenNotPaused returns (uint256) {
        uint256 newTokenId = _getNextTokenId();
        _mint(_msgSender(), newTokenId);
        _setTokenURI(newTokenId, metadataUri);
        adNfts[newTokenId] = AdNFT(0, 0);

        emit AdNFTCreated(newTokenId, metadataUri);

        return newTokenId;
    }

    function stakeOnAd(uint256 tokenId, uint256 amount) public whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        stakes[tokenId][_msgSender()] += amount;
        adNfts[tokenId].totalStake += amount;
        require(stakingToken.transferFrom(_msgSender(), address(this), amount), "Stake transfer failed");
        emit StakeUpdated(tokenId, _msgSender(), amount);
    }

    function claimRewards(uint256 tokenId) public whenNotPaused {
        uint256 stakedAmount = stakes[tokenId][_msgSender()];
        require(stakedAmount > 0, "Nothing to claim");

        uint256 reward = calculateReward(tokenId, _msgSender());
        stakes[tokenId][_msgSender()] = 0;
        adNfts[tokenId].totalStake -= stakedAmount;
        require(stakingToken.transfer(_msgSender(), stakedAmount + reward), "Reward transfer failed");
        emit RewardClaimed(tokenId, _msgSender(), reward);
    }

    function calculateReward(uint256 tokenId, address staker) public view returns (uint256) {
        AdNFT memory adNft = adNfts[tokenId];
        uint256 stakerShare = stakes[tokenId][staker];
        uint256 reward = adNft.engagementScore * stakerShare / adNft.totalStake * rewardRate;
        return reward;
    }

    function setRewardRate(uint256 _newRewardRate) external onlyRole(ADMIN_ROLE) {
        rewardRate = _newRewardRate;
    }

    function updateEngagementScore(uint256 tokenId, uint256 newScore) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        adNfts[tokenId].engagementScore = newScore;
        emit AdEngagementUpdated(tokenId, newScore);
    }

    function _getNextTokenId() private view returns (uint256) {
        return totalSupply() + 1;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // Chainlink Oracle parameters
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    
    // Mapping the request ID returned from Chainlink to the tokenId
    mapping(bytes32 => uint256) private requestToTokenId;

    // Events
    event OracleRequestMade(uint256 indexed tokenId, bytes32 requestId);
    event OracleSettingsUpdated(address oracle, bytes32 jobId, uint256 fee);
    
    // Function to set the oracle settings - only callable by the admin
    function setOracleSettings(
        address _oracle,
        string calldata _jobId,
        uint256 _fee
    ) external onlyRole(ADMIN_ROLE) {
        oracle = _oracle;
        jobId = stringToBytes32(_jobId);
        fee = _fee;
        emit OracleSettingsUpdated(_oracle, jobId, _fee);
    }

    // Function to convert a string to a bytes32
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly { // solhint-disable-line no-inline-assembly
            result := mload(add(source, 32))
        }
    }

    // Function to request the engagement data for an NFT
    function requestEngagementData(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillEngagementData.selector);

        // Add a parameter to the request that specifies which NFT we're interested in.
        request.add("get", string(abi.encodePacked(apiBaseURL, tokenId))); // `apiBaseURL` should be defined elsewhere in your contract

        // Send the request
        bytes32 requestId = sendChainlinkRequestTo(oracle, request, fee);
        requestToTokenId[requestId] = tokenId;

        emit OracleRequestMade(tokenId, requestId);
    }

    // Callback function for Chainlink Oracle to call with the engagement score
    function fulfillEngagementData(bytes32 _requestId, uint256 _engagementScore) external recordChainlinkFulfillment(_requestId) {
        uint256 tokenId = requestToTokenId[_requestId];
        require(_exists(tokenId), "NFT does not exist");

        updateEngagementScore(tokenId, _engagementScore);

        // Optionally remove the mapping if it is a one-off request
        delete requestToTokenId[_requestId];
    }

    // Other existing functions...

}