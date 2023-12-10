// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Import contracts and libraries
import "@ccip/contracts/ccip/interfaces/IRouterClient.sol";
import "@ccip/contracts/shared/access/OwnerIsCreator.sol";
import "@ccip/contracts/ccip/libraries/Client.sol";
import "@ccip/contracts/ccip/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract NFTCrossChainTransfer is ERC721URIStorage, AccessControlEnumerable, Pausable, CCIPReceiver, OwnerIsCreator {
    using SafeMath for uint256; // Use SafeMath for safer arithmetic operations

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    string public apiBaseURL = "https://adcraft.com/api/data/";  // EXAMPLE

    IERC20 private stakingToken;

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    // NFT details structure
    struct AdNFT {
        uint256 engagementScore;
        uint256 totalStake;
    }

    mapping(uint256 => AdNFT) public adNfts; // Mapping from tokenId to AdNFT details
    mapping(uint256 => mapping(address => uint256)) public stakes; // Mapping from tokenId to staker to staked amount

    // Events
    event AdNFTCreated(uint256 indexed tokenId, string metadataUri);
    event AdEngagementUpdated(uint256 indexed tokenId, uint256 engagementScore);
    event StakeUpdated(uint256 indexed tokenId, address indexed staker, uint256 amount);
    event RewardClaimed(uint256 indexed tokenId, address indexed staker, uint256 reward);
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        string text,
        address token,
        uint256 tokenAmount
    );

    constructor(
        address _stakingToken,
        uint256 _rewardRate
    ) ERC721("AdCraftNFT", "ACNFT") {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;

        _setupRoles(); // Initialize roles during contract deployment
    }

    // Function to set up roles
    function _setupRoles() internal {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

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

    // Function to create a new AdNFT - only callable by admins
    function createAdNFT(string calldata metadataUri) external onlyRole(ADMIN_ROLE) whenNotPaused returns (uint256) {
        uint256 newTokenId = _getNextTokenId();
        _mint(_msgSender(), newTokenId);
        _setTokenURI(newTokenId, metadataUri);
        adNfts[newTokenId] = AdNFT(0, 0);

        emit AdNFTCreated(newTokenId, metadataUri);

        return newTokenId;
    }

    // Function to stake on a specific AdNFT
    function stakeOnAd(uint256 tokenId, uint256 amount) public whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        stakes[tokenId][_msgSender()] += amount;
        adNfts[tokenId].totalStake += amount;
        require(stakingToken.transferFrom(_msgSender(), address(this), amount), "Stake transfer failed");
        emit StakeUpdated(tokenId, _msgSender(), amount);
    }

    // Function to claim rewards for a specific AdNFT
    function claimRewards(uint256 tokenId) public whenNotPaused {
        uint256 stakedAmount = stakes[tokenId][_msgSender()];
        require(stakedAmount > 0, "Nothing to claim");

        uint256 reward = calculateReward(tokenId, _msgSender());
        stakes[tokenId][_msgSender()] = 0;
        adNfts[tokenId].totalStake -= stakedAmount;
        require(stakingToken.transfer(_msgSender(), stakedAmount + reward), "Reward transfer failed");
        emit RewardClaimed(tokenId, _msgSender(), reward);
    }

    // Function to calculate the reward for a specific AdNFT and staker
    function calculateReward(uint256 tokenId, address staker) public view returns (uint256) {
        AdNFT memory adNft = adNfts[tokenId];
        uint256 stakerShare = stakes[tokenId][staker];
        uint256 reward = adNft.engagementScore.mul(stakerShare).div(adNft.totalStake).mul(rewardRate);
        return reward;
    }

    // Function to set the reward rate - only callable by admins
    function setRewardRate(uint256 _newRewardRate) external onlyRole(ADMIN_ROLE) {
        rewardRate = _newRewardRate;
    }

    // Function to update the engagement score for a specific AdNFT - only callable by admins
    function updateEngagementScore(uint256 tokenId, uint256 newScore) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        adNfts[tokenId].engagementScore = newScore;
        emit AdEngagementUpdated(tokenId, newScore);
    }

    // Function to get the next available tokenId
    function _getNextTokenId() private view returns (uint256) {
        return totalSupply() + 1;
    }

    // Function to pause the contract - only callable by admins
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    // Function to unpause the contract - only callable by admins
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // Function to request engagement data for a specific AdNFT from Chainlink Oracle - only callable by admins
    function requestEngagementData(uint256 tokenId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillEngagementData.selector);

        request.add("get", string(abi.encodePacked(apiBaseURL, tokenId)));

        bytes32 requestId = sendChainlinkRequestTo(oracle, request, fee);

        requestToTokenId[requestId] = tokenId;

        emit OracleRequestMade(tokenId, requestId);
    }

    // Callback function for Chainlink Oracle to update engagement score for a specific AdNFT
    function fulfillEngagementData(bytes32 _requestId, uint256 _engagementScore) external recordChainlinkFulfillment(_requestId) {
        uint256 tokenId = requestToTokenId[_requestId];
        require(_exists(tokenId), "NFT does not exist");

        updateEngagementScore(tokenId, _engagementScore);

        delete requestToTokenId[_requestId];
    }

    // Function to send data and transfer tokens to receiver on the destination chain - only callable by admins
    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount
    )
        external
        onlyRole(ADMIN_ROLE)
        onlyAllowlistedDestinationChain(_destinationChainSelector)
    {
        // Build the CCIP message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _text,
            _token,
            _amount,
            address(stakingToken) // Pay fees in stakingToken
        );

        // Get the router interface
        IRouterClient router = IRouterClient(getRouter());

        // Get fees for the message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        // Check if the contract has enough balance to cover the fees
        require(fees <= stakingToken.balanceOf(address(this)), "Not enough balance for fees");

        // Approve the Router to transfer stakingToken on contract's behalf
        require(stakingToken.approve(address(router), fees), "Failed to approve stakingToken transfer");

        // Send the message through the router
        bytes32 messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit the MessageSent event
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _text,
            _token,
            _amount,
            address(stakingToken),
            fees
        );
    }

    // Function to construct a CCIP message
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Create an array for token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        // Construct the CCIP message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_text),
                tokenAmounts: tokenAmounts,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: 200_000, strict: false })
                ),
                feeToken: _feeTokenAddress
            });
    }
}
