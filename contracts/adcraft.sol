// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import contracts and libraries
 
 /**
  * @title adCraft Contract
  * @notice This smart contract for AdCraft
  */

/**
 * @bro tip replace @ccip/contracts/ccip -> with -> smartcontractkit/ccip/tree/ccip-develop/contracts/src/v0.8
 * When using Remix IDE
 */
import "@ccip/contracts/ccip/interfaces/IRouterClient.sol";
import "@ccip/contracts/shared/access/OwnerIsCreator.sol";
import "@ccip/contracts/ccip/libraries/Client.sol";
import "@ccip/contracts/ccip/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract adCraft is ERC721URIStorage, AccessControlEnumerable, Pausable, CCIPReceiver, OwnerIsCreator {
    /// @notice SafeMath for safer arithmetic operations
    using SafeMath for uint256; 

    ///@notice Default role of the contract owner
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    ///@notice Base url for adcraft protocol
    string public apiBaseURL = "https://adcraft.com/api/data/"; 

    ///@notice Staking token on ads created on adcraft protocol
    IERC20 private stakingToken;

    ///@notice address of the chainlink DON
    address private oracle;
    ///@notice oracle job identifier(id)
    bytes32 private jobId;
    ///@notice fee to execute on the chainlink oracle
    uint256 private fee;

    ///@notice NFT details structure
    struct AdNFT {
        uint256 engagementScore;
        uint256 totalStake;
    }
    //=========================== Modifiers ==================================
    modifier onlyCompatibleChain(uint64 chainSelector) {
        require(supportedChains[chainSelector], "Chain not compatible");
        _;
    }

    //=========================== Mapped Storages =================================

    ///@notice Mapping from tokenId to AdNFT details
    mapping(uint256 => AdNFT) public adNfts; 

    ///@notice Mapping from tokenId to staker to staked amount
    mapping(uint256 => mapping(address => uint256)) public stakes; 

    ///@notice Mapping to track burned NFTs
    mapping(uint256 => bool) public isBurned; 

    ///@notice Mapping to keep track of bound NFTs
    mapping(uint256 => bool) public isNFTBound; 

    ///@notice Mapping to keep track of compatible chains based on their selectors
    mapping(uint64 => bool) public supportedChains;

    //================================== Events =================================

    ///@notice AdNFTCreated event emitted when an ad is successfully created
    event AdNFTCreated(uint256 indexed tokenId, string metadataUri);

    ///@notice AdEngagementUpdated event emitted when an ad engagement data is successfully updated
    event AdEngagementUpdated(uint256 indexed tokenId, uint256 engagementScore);

    ///@notice ChainCompatibilityUpdated event emitted when a chain is successfully updated
    event ChainCompatibilityUpdated(uint64 indexed chainSelector, bool isCompatible);

    ///@notice StakeUpdated event emitted when a stake for an ad is successfully updated
    event StakeUpdated(uint256 indexed tokenId, address indexed staker, uint256 amount);

    ///@notice RewardClaimed event emitted when a reward is successfully claimed by a staker
    event RewardClaimed(uint256 indexed tokenId, address indexed staker, uint256 reward);

    ///@notice MessageSent event is emitted when a message is sent to a destination chain from the source chain
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

    ///@notice MessageReceived is the event that is emitted when the message is received from a source chain to a destination chain.
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        string text,
        address token,
        uint256 tokenAmount
    );

    ///@notice NFTMoved event is emitted when an NFT is successfully moved from on chain to another
    event NFTMoved(
        uint256 indexed tokenId, 
        uint64 indexed destinationChainSelector
    );

    ///@notice NFTBound is emitted when an NFT is successfully bounded to a creator of the ad
    event NFTBound(
        uint256 indexed tokenId
    );


    /**
     * @notice constructor for adscraft client
     * @param _stakingToken - The token to be used to stake on ads
     * @param _rewardRate - The rate amount at which stakers will be rewarded 
     */
    constructor(
        address _stakingToken,
        uint256 _rewardRate
    ) ERC721("AdCraftNFT", "ACNFT") {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;

        _setupRoles(); 
    }

    /**
     * @notice Function to check if an NFT is bound for staking
     * @param tokenId - the token id to be checked
     */
    function getBindingStatus(uint256 tokenId) external view returns (bool) {
        return isNFTBound[tokenId];
    }

    /**
     * @notice Function to stake on a specific AdNFT
     * @param tokenId - the token identifier(id) to stake on
     * @param amount - the amount to stake
     */
    function stakeOnAd(uint256 tokenId, uint256 amount) public whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        stakes[tokenId][_msgSender()] += amount;
        adNfts[tokenId].totalStake += amount;
        require(stakingToken.transferFrom(_msgSender(), address(this), amount), "Stake transfer failed");
        emit StakeUpdated(tokenId, _msgSender(), amount);
    }

    /**
     * @notice Function to transfer tokens between addresses
     * @param to - address to transfer token to
     * @param amount - amount to transfer
     */
    function transfer(address to, uint256 amount) external whenNotPaused {
        require(stakingToken.transfer(to, amount), "Transfer failed");
    }

    /**
     * @notice Function to retrieve token balance of a specific address
     * @param account - the account to check balance for
     */
    function balanceOf(address account) external view returns (uint256) {
        return stakingToken.balanceOf(account);
    }

    /**
     * @notice Function to allow another address to spend tokens on behalf of the owner
     * @param spender - the spender address
     * @param amount - the amount allowable to spend
     */
    function approve(address spender, uint256 amount) external whenNotPaused returns (bool) {
        return stakingToken.approve(spender, amount);
    }

    /**
     * @notice Function to claim rewards for a specific AdNFT
     * @param tokenId - the id of the token to claim a reward for
     */
    function claimRewards(uint256 tokenId) public whenNotPaused {
        uint256 stakedAmount = stakes[tokenId][_msgSender()];
        require(stakedAmount > 0, "Nothing to claim");

        uint256 reward = calculateReward(tokenId, _msgSender());
        stakes[tokenId][_msgSender()] = 0;
        adNfts[tokenId].totalStake -= stakedAmount;
        require(stakingToken.transfer(_msgSender(), stakedAmount + reward), "Reward transfer failed");
        emit RewardClaimed(tokenId, _msgSender(), reward);
    }

    /**
     * @notice Function to calculate the reward for a specific AdNFT and staker
     * @param tokenId - the token identifier(id) to calculate reward for
     * @param staker  - the staker to calculate reward for
     */
    function calculateReward(uint256 tokenId, address staker) public view returns (uint256) {
        AdNFT memory adNft = adNfts[tokenId];
        uint256 stakerShare = stakes[tokenId][staker];
        uint256 reward = adNft.engagementScore.mul(stakerShare).div(adNft.totalStake).mul(rewardRate);
        return reward;
    }



    /**
     * @notice Function to get the next available tokenId  
     */
    function _getNextTokenId() private view returns (uint256) {
        return totalSupply() + 1;
    }

    /**
     * @notice  Function to check if a chain is compatible for NFT movement
     * @param chainSelector - the chain selector to check for compactibility
     */
    function checkChainCompatibility(uint64 chainSelector) external view returns (bool) {
        return supportedChains[chainSelector];
    }

    /**
     * @notice Function to buy AI NFTs in the marketplace on different chains
     * @param _destinationChainSelector - The selector of the destination chain (where the target transaction is to be made)
     * @param _receiver address of the buyer of the NFT token
     * @param _nftMetadataUri - the NFT metadata URI
     * @param _nftTokenAddress - the NFT token address
     * @param _nftTokenId - the NFT token identifier(ID)
     * @param _paymentToken - the payment token address (native token only)
     * @param _paymentAmount - the payment token amount 
     */

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
        onlyAllowlistedDestinationChain(_destinationChainSelector)
    {
        // Build the CCIP message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessageBuyNFT(
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

    
    //======================================== INTERNAL FUNCTIONS =================================

    /**
     * @notice Function to set up roles
     */
    function _setupRoles() internal {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    /**
     * @notice Internal Function to build CCIP message to buy NFT's
     * @param _receiver address of the buyer of the NFT token
     * @param _nftMetadataUri - the NFT metadata URI
     * @param _nftTokenAddress - the NFT token address
     * @param _nftTokenId - the NFT token identifier(ID)
     * @param _paymentToken - the payment token (native token only)
     * @return Client.EVM2AnyMessage structure for CCIP internal implementations
     */
    function _buildCCIPMessageBuyNFT(
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

    /**
     * @notice Internal function to build CCIP message to transfer tokens/by stake on ads from different chain
     * @param _receiver contract address receiver on the destination chain
     * @param _text - the text/message to be sent
     * @param _token - the token address to be sent
     * @param _amount - the amount to be sent
     * @param _feeTokenAddress - the fee token address to pay gas fee on destination chain with
     */
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

    //======================================== ADMIN ================================

    /**
     * @notice Function to set the oracle settings - only callable by the admin
     * @param _oracle - address of the Oracle
     * @param _jobId - job id to be used/referenced by the oracle
     * @param _fee - fee to deliver the job from the Oracle by chainlink
     */
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

    /**
     * @notice Owner-only function to add or remove compatible chains
     * @param chainSelector - the chain selector to update 
     * @param isCompatible - boolean indicating if the chain is compatible
     */

    function updateChainCompatibility(uint64 chainSelector, bool isCompatible) external onlyOwner {
        supportedChains[chainSelector] = isCompatible;
        emit ChainCompatibilityUpdated(chainSelector, isCompatible);
    }

       /**
     * @notice Function use to send tokens for staking on an adcraft ads cross chain, and pay fees in the staked tokens
     * @param _destinationChainSelector - The selector of the destination chain (where the target transaction is to be made)
     * @param _receiver - The receiver of the transaction (where the target transaction is to be made) contract address
     * @param _text - The text to be sent along with the transaction
     * @param _token - The token to be sent along with the transaction
     * @param _amount - The amount to be sent along with the transaction
     */

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

    /**
     * @notice Function to move an ad-related NFT to another compatible blockchain
     * @param tokenId - the NFT token identifier(ID)
     * @param destinationChainSelector - the destination chain selector for the target chain where the NFT is to be moved
     */

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


    /**
     * @notice Function to request engagement data for a specific AdNFT from Chainlink Oracle - only callable by admins
     * @param tokenId - token identifier(id) that a request for engagement data will be sent made for
     */
    function requestEngagementData(uint256 tokenId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillEngagementData.selector);

        request.add("get", string(abi.encodePacked(apiBaseURL, tokenId)));

        bytes32 requestId = sendChainlinkRequestTo(oracle, request, fee);

        requestToTokenId[requestId] = tokenId;

        emit OracleRequestMade(tokenId, requestId);
    }

    /**
     * @notice Function to pause the contract - only callable by admins
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Function to resume the contract - only callable by admins
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Function to set the reward rate - only callable by admins
     * @param _newRewardRate - the new reward rate to be updated 
     */
    function setRewardRate(uint256 _newRewardRate) external onlyRole(ADMIN_ROLE) {
        rewardRate = _newRewardRate;
    }

    /**
     * @notice Function to update the engagement score for a specific AdNFT - only callable by admins
     * @param tokenId - the token identifier(id) of the ads to be updated
     * @param newScore - the new score of the ads
     */
    function updateEngagementScore(uint256 tokenId, uint256 newScore) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        adNfts[tokenId].engagementScore = newScore;
        emit AdEngagementUpdated(tokenId, newScore);
    }

    /**
     * @notice Function to bind an NFT with staking properties for ad creators
     * @param tokenId - the token identifier(id) to be bind to creators
     */
    function bindAdNFT(uint256 tokenId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_exists(tokenId), "NFT does not exist");
        require(!isNFTBound[tokenId], "NFT already bound");

        // Mark the NFT as bound
        isNFTBound[tokenId] = true;

        emit NFTBound(tokenId);
    }


    /**
     * @notice Function to create a new AdNFT - only callable by admins
     * @param metadataUri - the metadataURI of the ad to be created
     */
    function createAdNFT(string calldata metadataUri) external onlyRole(ADMIN_ROLE) whenNotPaused returns (uint256) {
        uint256 newTokenId = _getNextTokenId();
        _mint(_msgSender(), newTokenId);
        _setTokenURI(newTokenId, metadataUri);
        adNfts[newTokenId] = AdNFT(0, 0);

        emit AdNFTCreated(newTokenId, metadataUri);

        return newTokenId;
    }

    //===================================== CALLBACKS =================================

    /**
     * @notice Callback function for Chainlink Oracle to update engagement score for a specific AdNFT
     * @param _requestId - request id for fulfillment of engagement data, request from chainlink oracle
     * @param _engagementScore - the value of the current engagement score
     */
    function fulfillEngagementData(bytes32 _requestId, uint256 _engagementScore) external recordChainlinkFulfillment(_requestId) {
        uint256 tokenId = requestToTokenId[_requestId];
        require(_exists(tokenId), "NFT does not exist");

        updateEngagementScore(tokenId, _engagementScore);

        delete requestToTokenId[_requestId];
    }
}