// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import contracts and libraries
import "@ccip/contracts/ccip/interfaces/IRouterClient.sol";
import "@ccip/contracts/shared/access/OwnerIsCreator.sol";
import "@ccip/contracts/ccip/libraries/Client.sol";
import "@ccip/contracts/ccip/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract adCraft is ERC721URIStorage, AccessControlEnumerable, Pausable, CCIPReceiver, OwnerIsCreator {
    using SafeMath for uint256; // SafeMath for safer arithmetic operations

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    string public apiBaseURL = "https://adcraft.com/api/data/"; // EXAMPLE

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
    mapping(uint256 => bool) public isBurned; // Mapping to track burned NFTs
    mapping(uint256 => bool) public isNFTBound; // Mapping to keep track of bound NFTs
    mapping(uint64 => bool) public supportedChains; // Mapping to keep track of compatible chains based on their selectors

    // Events
    event AdNFTCreated(uint256 indexed tokenId, string metadataUri);
    event AdEngagementUpdated(uint256 indexed tokenId, uint256 engagementScore);
     event ChainCompatibilityUpdated(uint64 indexed chainSelector, bool isCompatible);
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
    event NFTMoved(
        uint256 indexed tokenId, 
        uint64 indexed destinationChainSelector
    );
    event NFTBound(
        uint256 indexed tokenId
    );

    constructor(
        address _stakingToken,
        uint256 _rewardRate
    ) ERC721("AdCraftNFT", "ACNFT") {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;

        _setupRoles(); 
    }

    // Function to set up roles
    function _setupRoles() internal {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    modifier onlyCompatibleChain(uint64 chainSelector) {
        require(supportedChains[chainSelector], "Chain not compatible");
        _;
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

    // Function to bind an NFT with staking properties for ad creators
    function bindAdNFT(uint256 tokenId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        require(!isNFTBound[tokenId], "NFT already bound");

        // Mark the NFT as bound
        isNFTBound[tokenId] = true;

        emit NFTBound(tokenId);
    }

    // Function to check if an NFT is bound for staking
    function getBindingStatus(uint256 tokenId) external view returns (bool) {
        return isNFTBound[tokenId];
    }

    // Function to stake on a specific AdNFT
    function stakeOnAd(uint256 tokenId, uint256 amount) public whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        stakes[tokenId][_msgSender()] += amount;
        adNfts[tokenId].totalStake += amount;
        require(stakingToken.transferFrom(_msgSender(), address(this), amount), "Stake transfer failed");
        emit StakeUpdated(tokenId, _msgSender(), amount);
    }

    // Function to transfer tokens between addresses
    function transfer(address to, uint256 amount) external whenNotPaused {
        require(stakingToken.transfer(to, amount), "Transfer failed");
    }

    // Function to retrieve token balance of a specific address
    function balanceOf(address account) external view returns (uint256) {
        return stakingToken.balanceOf(account);
    }

    // Function to allow another address to spend tokens on behalf of the owner
    function approve(address spender, uint256 amount) external whenNotPaused returns (bool) {
        return stakingToken.approve(spender, amount);
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

    // Function to check if a chain is compatible for NFT movement
    function checkChainCompatibility(uint64 chainSelector) external view returns (bool) {
        return supportedChains[chainSelector];
    }

    // Owner-only function to add or remove compatible chains
    function updateChainCompatibility(uint64 chainSelector, bool isCompatible) external onlyOwner {
        supportedChains[chainSelector] = isCompatible;
        emit ChainCompatibilityUpdated(chainSelector, isCompatible);
    }

    // Function to move an ad-related NFT to another compatible blockchain
    function moveToChain(uint256 tokenId, uint64 destinationChainSelector) external onlyRole(ADMIN_ROLE) whenNotPaused onlyCompatibleChain(destinationChainSelector) {
        require(_exists(tokenId), "NFT does not exist");
        require(!isBurned[tokenId], "NFT already burned");

        // Burn the NFT on the current chain
        _burn(tokenId);

        // Mark the NFT as burned
        isBurned[tokenId] = true;

        // Get metadata URI of the NFT
        string memory metadataUri = tokenURI(tokenId);

        // Initiate the transfer of relevant information to the destination chain
        bytes32 messageId = sendMessagePayNative(
            destinationChainSelector,
            address(this), // Assuming the NFT is transferred to this contract on the destination chain
            metadataUri,
            address(this), // Token address on the destination chain
            tokenId // Token ID can be used as a unique identifier on the destination chain
        );
        // Emit an event indicating that the NFT is being moved to another chain
        emit NFTMoved(tokenId, destinationChainSelector);
    }

    // Function to send a CCIP message and pay the fees in stakingToken
    function sendMessagePayNative(
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
            }
        );
    }

    // Function to buy AI NFTs in the marketplace on different chains
    function buyAINFT(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _nftMetadataUri,
        address _nftTokenAddress,
        uint256 _nftTokenId,
        address _paymentToken,
        uint256 _paymentAmount
    )
        external
        onlyRole(ADMIN_ROLE)
        onlyAllowlistedDestinationChain(_destinationChainSelector)
    {
        // Build the CCIP message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _nftMetadataUri,
            _nftTokenAddress,
            _nftTokenId,
            _paymentToken
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
            _nftMetadataUri,
            _nftTokenAddress,
            _nftTokenId,
            _paymentToken,
            _paymentAmount
        );
    }

    // Function to construct a CCIP message for buying NFTs
    function _buildCCIPMessage(
        address _receiver,
        string calldata _nftMetadataUri,
        address _nftTokenAddress,
        uint256 _nftTokenId,
        address _paymentToken
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Create an array for token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](2);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _nftTokenAddress,
            amount: _nftTokenId
        });
        tokenAmounts[1] = Client.EVMTokenAmount({
            token: _paymentToken,
            amount: 0 // Amount will be set by the router on the destination chain
        });

        // Construct the CCIP message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_nftMetadataUri),
                tokenAmounts: tokenAmounts,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: 200_000, strict: false })
                ),
                feeToken: address(0) // Fees are paid in native gas
            }
        );
    }
}