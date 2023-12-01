// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AdCraftPlatform is ERC721, AccessControlEnumerable, ChainlinkClient {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    using Chainlink for Chainlink.Request;
    
    // Oracle parameters
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    // Staking token (ERC20)
    IERC20 private stakingToken;

    // NFT details structure
    struct AdNFT {
        string adContentUri;
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
    event AdEngagementUpdated(uint256 indexed tokenId, uint256 engagementScore);
    event StakeUpdated(uint256 indexed tokenId, address indexed staker, uint256 amount);
    event RewardClaimed(uint256 indexed tokenId, address indexed staker, uint256 reward);
    event OracleSettingsUpdated(address oracle, bytes32 jobId, uint256 fee);

    constructor(
        address _linkToken, 
        address _oracle, 
        string memory _jobId, 
        uint256 _fee, 
        address _stakingToken,
        uint256 _rewardRate
    ) ERC721("AdCraftNFT", "ACNFT") {
        // Setup Chainlink
        setChainlinkToken(_linkToken);
        oracle = _oracle;
        jobId = bytes32(abi.encodePacked(_jobId));
        fee = _fee;

        // Initialize the staking token and reward rate
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    // Modifier to check the admin role
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Caller is not an admin");
        _;
    }

    // Function to change the oracle settings
    function setOracleSettings(address _oracle, string calldata _jobId, uint256 _fee) external onlyOwner {
        oracle = _oracle;
        jobId = bytes32(abi.encodePacked(_jobId));
        fee = _fee;
        emit OracleSettingsUpdated(_oracle, jobId, _fee);
    }

    // Function to set a new reward rate
    function setRewardRate(uint256 _newRewardRate) external onlyOwner {
        rewardRate = _newRewardRate;
    }

    // Function to create Ad-NFT with metadata URI
    function createAdNFT(uint256 tokenId, string calldata adContentUri) external onlyAdmin {
        _mint(_msgSender(), tokenId);
        adNfts[tokenId] = AdNFT(adContentUri, 0, 0);
    }

    // Function to stake tokens on an Ad-NFT
    function stakeOnAd(uint256 tokenId, uint256 amount) external {
        require(_exists(tokenId), "NFT does not exist");
        stakes[tokenId][_msgSender()] += amount;
        adNfts[tokenId].totalStake += amount;
        require(stakingToken.transferFrom(_msgSender(), address(this), amount), "Stake transfer failed");
        emit StakeUpdated(tokenId, _msgSender(), amount);
    }

    // Function to request engagement data for an Ad-NFT
    mapping(bytes32 => uint256) private requestToTokenId;

    function requestEngagementData(uint256 tokenId) external onlyAdmin returns (bytes32 requestId) {
    Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillEngagementData.selector);
    // Set additional parameters for the request

    // ... other request parameters setup ...

    // Send Chainlink Request
    bytes32 requestId = sendChainlinkRequestTo(oracle, request, fee);
    
    // Store request ID to tokenId mapping
    requestToTokenId[requestId] = tokenId;
    
    return requestId;
    }

    // Callback function for Chainlink oracle's response
    function fulfillEngagementData(bytes32 _requestId, uint256 _engagementScore) external recordChainlinkFulfillment(_requestId) {
    // Retrieve the tokenId from the request ID
    uint256 tokenId = requestToTokenId[_requestId];
    require(tokenId != 0, "Request ID is not valid");

    // Update the engagement score associated with the NFT tokenId
    adNfts[tokenId].engagementScore = _engagementScore;

    // Emit an event
    emit AdEngagementUpdated(tokenId, _engagementScore);

    // Clean up the request mapping if it's a single use
    delete requestToTokenId[_requestId];
    }

    // Function for users to withdraw their stake and claim rewards
    function claimRewards(uint256 tokenId) external {
        uint256 stakedAmount = stakes[tokenId][_msgSender()];
        require(stakedAmount > 0, "Nothing to claim");
        
        uint256 reward = calculateReward(tokenId, _msgSender());
        stakes[tokenId][_msgSender()] = 0;
        adNfts[tokenId].totalStake -= stakedAmount;
        
        require(stakingToken.transfer(_msgSender(), stakedAmount + reward), "Reward transfer failed");
        emit RewardClaimed(tokenId, _msgSender(), reward);
    }

    // Function to calculate the reward for a stakeholder based on engagement data
    function calculateReward(uint256 tokenId, address staker) public view returns (uint256 reward) {
        AdNFT memory adNft = adNfts[tokenId];
        uint256 stakerShare = stakes[tokenId][staker];

        // Reward calculation logic based on engagement data
        reward = adNft.engagementScore * stakerShare / adNft.totalStake * rewardRate;
        return reward;
    }
}