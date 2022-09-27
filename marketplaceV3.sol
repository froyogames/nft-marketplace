// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";



contract MarketplaceV1 is AccessControl, ReentrancyGuard{
    using Counters for Counters.Counter;
    Counters.Counter private _items;
    Counters.Counter private _soldItems;

    address payable owner;
    address public froyoContract;
    bool marketPlaceToggle = true;
    mapping(address => bool) whitelistedAddresses;


    uint256 platform_fee; // default is 10%

    // interface to marketplace item
    struct MarketplaceItem {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        uint256 froyoPrice;
        SalesAttributes salesProperty;
        bool isListed;
        bool sold;
    }

    struct SalesAttributes{
        uint256 salesType;
        uint256 duration;
        uint discountRate;
        uint startAt;
        uint expiresAt;
    }
    

    MarketplaceItem[] private idToMarketplaceItem; //change it to private after done 
    
    error NotApprovedForMarketplace();
    /*
     * declare a event for when a item is created on marketplace
     * salesCurrency=1 is for bnb token fixed sales
     * salesCurrency=2 is for froyo token fixed sales
     * 
     */
    event MarketplaceItemCreated(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        uint256 salesCurrency,
        uint256 salesDuration,
        uint256 expiredAt,
        uint256 MarketVersion
    );

    // declare a event for when a item is canceled on marketplace
    event MarketplaceItemCanceled(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price,
        uint256 salesDuration,
        uint256 salesCurrency,
        uint256 expiredAt,
        uint256 MarketVersion
    );

    event MarketplaceItemSold(
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 salesDuration,
        uint256 salesCurrency,
        uint256 expiredAt,
        uint256 price,
        bool sold,
        uint256 MarketVersion
    );

    event ItemPriceUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        uint256 salesDuration,
        uint256 salesCurrency,
        uint256 expiredAt,
        uint256 MarketVersion
    );

    event ItemFroyoPriceUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 froyoprice,
        uint256 salesDuration,
        uint256 salesCurrency,
        uint256 expiredAt,
        uint256 MarketVersion
    );

    event ItemSalesDuration(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        uint256 salesDuration,
        uint256 salesCurrency,
        uint256 startAt,
        uint256 expiredAt,
        uint256 MarketVersion
    );

    event NewFroyoAdress(
        address indexed newFroyo
    );

    event MarketToggleStatus(
        bool status
    );

    event addWhitelistAddress(
        address indexed newAddress
    );

    event SetPercentageFees(
        uint256 fees
    );


    constructor(address _froyoContract) payable {
        owner = payable(msg.sender);
        froyoContract = _froyoContract;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    
    function setFroyoAddress(address _froyo) public onlyRole(DEFAULT_ADMIN_ROLE) {
        froyoContract = _froyo;
        emit NewFroyoAdress(_froyo);
    }

    function setMarketToggle(bool _stopMarket) public onlyRole(DEFAULT_ADMIN_ROLE) {
        marketPlaceToggle = _stopMarket;
        emit MarketToggleStatus(_stopMarket);
    }
    // Modifier to check that the caller is the owner of
    // the contract.
    modifier onlyFroyoOwner() {
        require(msg.sender == owner, "Not owner");
        // Underscore is a special character only used inside
        // a function modifier and it tells Solidity to
        // execute the rest of the code.
        _;
    }

    // Modifier to stop create new item in the marketplace.
    modifier MarketPlaceToggle() {
        require(marketPlaceToggle == true, "Market does not allow to list new item");
        // Underscore is a special character only used inside
        // a function modifier and it tells Solidity to
        // execute the rest of the code.
        _;
    }
    
    //checking of whitelist nft contract
    modifier isWhitelisted(address _address) {
        require(whitelistedAddresses[_address], "Contract need to be whitelisted!");
        _;
    }

    // Add whitelist nft contracts
    function addNftWhitelist(address _addressToWhitelist) public onlyFroyoOwner {
        whitelistedAddresses[_addressToWhitelist] = true;
        emit addWhitelistAddress(_addressToWhitelist);
    }

    // returns the percentageBasisPoints rate (in Wei) that owner charge for marketplace
    function getPlatformFees() public view returns (uint256) {
        return platform_fee;
    }

    // verify whitelist nft contracts 
    function verifyUser(address _whitelistedAddress) public view returns(bool) {
        bool userIsWhitelisted = whitelistedAddresses[_whitelistedAddress];
        return userIsWhitelisted;
    }


    /// Sets the percentageBasisPoints rate (in Wei) for this specific contract instance 
    /// 10000 wei is equivalent to 100%
    /// 1000 wei is equivalent to 10%
    /// 100 wei is equivalent to 1%
    /// 10 wei is equivalent to 0.1%
    /// 1 wei is equivalent to 0.01%
    /// Whereby a traditional floating point percentage like 8.54% would simply be 854 percentage basis points (or in terms of the ethereum uint256 variable, 854 wei)
    /// _newCost is the annual percentage yield as per the above instructions
    function setPlatformFees(uint256 _newCost) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newCost >= 0 && _newCost <= 10000, "Percentage must be a value >=0 and <= 10000");
        platform_fee = _newCost;
        emit SetPercentageFees(_newCost);
    }
    
    // places an item for sale on the marketplace
    // the seller must put a price for both currency(native + froyo)
    function CreateItemFixedPriceSales(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 isFroyo,
        uint256 _duration
    ) external isWhitelisted(nftContract)  MarketPlaceToggle nonReentrant {
        require(price > 0, "Price cannot be 0");
        require(isFroyo >=0 && isFroyo <= 1, "Only 0 and 1 is accepted!");
        require(_duration >= 0 , "Cannot be 0 days!"); 
        
        if (IERC721(nftContract).getApproved(tokenId) != address(this)) {
            revert NotApprovedForMarketplace();
        }
        
        _items.increment();
        uint256 itemId = _items.current();
        uint256 numberOfdays;
        numberOfdays = (_duration * 1 days);
        
        uint256 sales_currency;
        if (isFroyo == 0){
            sales_currency = 1;
        }
        else {
            sales_currency = 2;
        }

        emit MarketplaceItemCreated(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price,
            sales_currency,
            numberOfdays,
            block.timestamp + numberOfdays,
            1
        );


        if(isFroyo == 0) {

        idToMarketplaceItem.push(MarketplaceItem(
            itemId,
            nftContract,
            tokenId,
            payable(msg.sender),
            payable(address(0)),
            price,
            0,
            SalesAttributes(
                1,
                numberOfdays,
                0,
                block.timestamp,
                block.timestamp + numberOfdays
            ),
            true,
            false
            ));

        // payable(owner).transfer(listingPrice);
        IERC721(nftContract).transferFrom(msg.sender,address(this), tokenId);

        }
        else {
        idToMarketplaceItem.push(MarketplaceItem(
            itemId,
            nftContract,
            tokenId,
            payable(msg.sender),
            payable(address(0)),
            0,
            price,
            SalesAttributes(
                1,
                numberOfdays,
                0,
                block.timestamp,
                block.timestamp + numberOfdays
            ),
            true,
            false
            ));

        // payable(owner).transfer(listingPrice);
        IERC721(nftContract).transferFrom(msg.sender,address(this), tokenId);
        }

    }
    
    //Fetch item Id of the listed nft 
    function fetchItemId(address _nftcontract, uint _tokenId) isWhitelisted(_nftcontract) public view returns(uint){
        uint nftCount = idToMarketplaceItem.length;
        uint myItemId = 0;
        bool isItemListed = false;

        for (uint i = 0; i < nftCount; i++) {
            if (idToMarketplaceItem[i].nftContract == _nftcontract &&
                idToMarketplaceItem[i].tokenId == _tokenId && 
                idToMarketplaceItem[i].isListed == true
               ) 
            {
            myItemId = idToMarketplaceItem[i].itemId;
            isItemListed = true;
            }
        }
        
        if(isItemListed){
            return myItemId;
        }

        else {
            revert("Your item is not in marketplace!");
        }
        
    }
    
    //fetching both nft address and token id 
    function fetchNftAdressAndTokenId(uint _itemid) public view returns (address,uint) {
        if(idToMarketplaceItem[_itemid - 1].itemId == 0) {
            revert("NFT does not exist!");
        }
        address myItemAddrs = idToMarketplaceItem[_itemid -1].nftContract;
        uint256 myTokenID = idToMarketplaceItem[_itemid -1].tokenId;

        return (myItemAddrs,myTokenID);
    }
    
    //fetch BNB price of marketplace item  
    function fetchItemPriceFroyo(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
        
        if(idToMarketplaceItem[myItemid - 1].itemId == 0) {
            revert("NFT does not exist!");
        }
        require(idToMarketplaceItem[myItemid -1].price == 0, "The item does not accept BNB currency!");

        return idToMarketplaceItem[myItemid -1].froyoPrice;
    }

    function fetchItemPriceBNB(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
        
        if(idToMarketplaceItem[myItemid - 1].itemId == 0) {
            revert("NFT does not exist!");
        }
        require(idToMarketplaceItem[myItemid -1].froyoPrice == 0, "The item does not accept Froyo currency!");

        return idToMarketplaceItem[myItemid -1].price;
    }

    function getExpiredDate(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
        
        if(idToMarketplaceItem[myItemid - 1].itemId == 0) {
            revert("NFT does not exist!");
        }
        require(idToMarketplaceItem[myItemid -1].isListed == true ,"Your item does not exists!");

        return idToMarketplaceItem[myItemid -1].salesProperty.expiresAt;
    }

    function getMyListedNfts() public view returns (MarketplaceItem[] memory) {
        uint nftCount = idToMarketplaceItem.length;
        uint myListedNftCount = 0;
        for (uint i = 0; i < nftCount; i++) {
            if (idToMarketplaceItem[i].seller == msg.sender) {
            myListedNftCount++;
            }
        }

        MarketplaceItem[] memory nfts = new MarketplaceItem[](myListedNftCount);
        uint nftsIndex = 0;
        for (uint i = 0; i < nftCount; i++) {
            if (idToMarketplaceItem[i].seller == msg.sender) {
            nfts[nftsIndex] = idToMarketplaceItem[i];
            nftsIndex++;
            }
        }
        return nfts;
    }

    // creates the sale of a marketplace item
    // transfers ownership of the item, as well as funds between parties
    function BuyNftWithFroyo(address _nftContract, uint256 _tokenId)
        isWhitelisted(_nftContract) 
        public
        nonReentrant
    {
        uint256 itemId = fetchItemId(_nftContract, _tokenId);
        
        if(idToMarketplaceItem[itemId - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }

        uint256 price = idToMarketplaceItem[itemId - 1].froyoPrice;
        address seller = idToMarketplaceItem[itemId -1].seller;
        uint256 expiredSale = idToMarketplaceItem[itemId - 1].salesProperty.expiresAt;
        /*
         * Price already uses wei unit
         */
        require(idToMarketplaceItem[itemId - 1].sold == false, "The item is already sold!");
        require(
            IERC20(froyoContract).balanceOf(msg.sender) >= price,
            "Insufficient balance, please buy more FROYO in order to complete the purchase"
        );
        require(block.timestamp < expiredSale, "This sales has ended");
        require(idToMarketplaceItem[itemId -1].price == 0 ,"This item does not accept Froyo currency!");

        emit MarketplaceItemSold(
        _nftContract,
        idToMarketplaceItem[itemId - 1].tokenId,
        idToMarketplaceItem[itemId - 1].seller,
        idToMarketplaceItem[itemId - 1].owner,
        idToMarketplaceItem[itemId - 1].salesProperty.duration,
        2,
        idToMarketplaceItem[itemId - 1].salesProperty.expiresAt,
        idToMarketplaceItem[itemId - 1].froyoPrice,
        idToMarketplaceItem[itemId - 1].sold,
        1
        );
        
        IERC20(froyoContract).transferFrom(msg.sender,owner,((price*platform_fee)/10000));
        IERC20(froyoContract).transferFrom(msg.sender,seller,(price - ((price*platform_fee)/10000))); 
        IERC721(_nftContract).safeTransferFrom(address(this), msg.sender, idToMarketplaceItem[itemId - 1].tokenId);
        idToMarketplaceItem[itemId - 1].owner = payable(msg.sender);
        idToMarketplaceItem[itemId - 1].sold = true;
        
        _soldItems.increment();


    }

    function BuyNftFixedPriceSales(address _nftContract , uint _tokenId) 
        isWhitelisted(_nftContract)
        public 
        payable 
        nonReentrant 
    {
        uint256 _itemId = fetchItemId(_nftContract, _tokenId);
        if(idToMarketplaceItem[_itemId - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }

        uint256 price = idToMarketplaceItem[_itemId - 1].price;
        uint256 tokenId = idToMarketplaceItem[_itemId - 1].tokenId;
        uint256 expiredSale = idToMarketplaceItem[_itemId - 1].salesProperty.expiresAt;
        require(idToMarketplaceItem[_itemId - 1].sold == false, "The item is already sold!");
        require(block.timestamp < expiredSale, "This sales has ended");
        require(idToMarketplaceItem[_itemId -1].froyoPrice == 0 ,"The item does not accept BNB currency!");
        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );
        
        idToMarketplaceItem[_itemId - 1].owner = payable(msg.sender);
        idToMarketplaceItem[_itemId - 1].sold = true;
        
        emit MarketplaceItemSold(
        _nftContract,
        tokenId,
        idToMarketplaceItem[_itemId - 1].seller,
        idToMarketplaceItem[_itemId - 1].owner,
        idToMarketplaceItem[_itemId - 1].salesProperty.duration,
        1,
        idToMarketplaceItem[_itemId - 1].salesProperty.expiresAt,
        idToMarketplaceItem[_itemId - 1].price,
        idToMarketplaceItem[_itemId - 1].sold,
        1
        );
        
        uint256 buyPrice = msg.value;
        uint256 fees = (price*platform_fee)/10000;
        uint256 selling_price = buyPrice - fees;
        IERC721(_nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
     
        payable(idToMarketplaceItem[_itemId - 1].seller).transfer(selling_price);
        payable(owner).transfer(fees);

        _soldItems.increment();

    }

    function ChangeNftPriceFixedSales(address _nftcontract, uint _tokenid, uint _newprice) isWhitelisted(_nftcontract) public {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        
        if(idToMarketplaceItem[_itemid - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");
        require(idToMarketplaceItem[_itemid -1].froyoPrice == 0 ,"The item does not accept BNB currency!");
        require(idToMarketplaceItem[_itemid -1].sold == false, "The item had been sold!");
        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        

        emit ItemPriceUpdated(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        _newprice,
        idToMarketplaceItem[_itemid - 1].salesProperty.duration,
        1,
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt,
        1
        );

        idToMarketplaceItem[_itemid - 1].price = _newprice;

    }

    function ChangeNftPriceFixedSalesFroyo(address _nftcontract, uint _tokenid, uint _newprice) isWhitelisted(_nftcontract) public {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        if(idToMarketplaceItem[_itemid - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");
        require(idToMarketplaceItem[_itemid -1].price == 0 ,"This item does not accept Froyo currency!");
        require(idToMarketplaceItem[_itemid -1].sold == false, "This item had been sold!");
        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        

        emit ItemFroyoPriceUpdated(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        _newprice,
        idToMarketplaceItem[_itemid - 1].salesProperty.duration,
        2,
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt,
        1
        );

        idToMarketplaceItem[_itemid - 1].froyoPrice = _newprice;

    }


    function ChangeNftSalesDuration(address _nftcontract, uint _tokenid, uint _salesDuration) isWhitelisted(_nftcontract) public {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        
        if(idToMarketplaceItem[_itemid - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }
        // require(msg.value == listingPrice , "You are require to pay the listing fees!");
        // require(idToMarketplaceItem[_itemid -1].salesProperty.salesType == 1, "Applicable only for fixed price sales");
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");
        require(idToMarketplaceItem[_itemid - 1].sold == false, "The item had been sold!");
        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        
        uint256 fetchPrice;
        uint256 sales_currency;
        if (idToMarketplaceItem[_itemid - 1].price == 0) {
            fetchPrice = idToMarketplaceItem[_itemid - 1].froyoPrice;
            sales_currency = 2;
        }
        else {
            fetchPrice = idToMarketplaceItem[_itemid - 1].price;
            sales_currency = 1;
        }

        uint256 numberOfdays;
        numberOfdays = (_salesDuration * 1 days);
        idToMarketplaceItem[_itemid - 1].salesProperty.startAt = block.timestamp;
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt = block.timestamp + numberOfdays;
        
        emit ItemSalesDuration(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        fetchPrice,
        idToMarketplaceItem[_itemid - 1].salesProperty.duration,
        sales_currency,
        idToMarketplaceItem[_itemid - 1].salesProperty.startAt,
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt,
        1 
        );
        
        // payable(owner).transfer(listingPrice);

    }


    // fetch all marketplace items
    // return a tuple 
    function getAllActiveListedItems()
        public
        view
        returns (MarketplaceItem[] memory)
    {
        uint myLength = idToMarketplaceItem.length;
        uint nftsIndex = 0;

        for (uint i = 0; i < myLength; i++) {
            if (idToMarketplaceItem[i].itemId != 0) {
                nftsIndex++;
            }

        }

        MarketplaceItem[] memory nfts = new MarketplaceItem[](nftsIndex);
        
        uint _index = 0;

        for (uint i = 0; i < myLength; i++) {
            if (idToMarketplaceItem[i].itemId != 0) {
                nfts[_index] = idToMarketplaceItem[i];
                _index++;
            }
        }
        return nfts;
    }


    function getAllSellStatus()
        public
        view
        returns (bool[] memory)
    {
        uint myLength = idToMarketplaceItem.length;
        
        bool[] memory nfts = new bool[](myLength);
        uint nftsIndex = 0;
        for (uint i = 0; i < myLength; i++) {
            nfts[nftsIndex] = idToMarketplaceItem[i].sold;
            nftsIndex++;
        }
        return nfts;
    }

    function getTotalItemSold() 
        public 
        view 
        returns (uint)
    {
        uint solditem = _soldItems.current();

        return solditem; 

    }
    
    // remove item from marketplace
    // the seller must already created an item on the marketplace
    // and the item listed havent been sold yet
    function removeItemFromMarket(address _nftcontract,uint _tokenid) isWhitelisted(_nftcontract) public nonReentrant {
        uint256 _itemId = fetchItemId(_nftcontract, _tokenid);

        if(idToMarketplaceItem[_itemId - 1].itemId == 0) {
            revert("NFT does not existed, item had been removed from marketplace!");
        }

        require(idToMarketplaceItem[_itemId - 1].seller == msg.sender, "You are not the owner!");
        
        uint256 sales_currency;
        if (idToMarketplaceItem[_itemId -1].price != 0){
            sales_currency = 1;
        }
        else {
            sales_currency = 2;
        }

        if (idToMarketplaceItem[_itemId - 1].seller == msg.sender && 
            idToMarketplaceItem[_itemId - 1].sold == false &&
            idToMarketplaceItem[_itemId - 1].itemId == _itemId && 
            idToMarketplaceItem[_itemId - 1].isListed == true) 
            {
                emit MarketplaceItemCanceled(
                    _itemId,
                    idToMarketplaceItem[_itemId -1].nftContract,
                    idToMarketplaceItem[_itemId - 1].tokenId,
                    idToMarketplaceItem[_itemId - 1].seller,
                    idToMarketplaceItem[_itemId - 1].price,
                    idToMarketplaceItem[_itemId - 1].salesProperty.duration,
                    sales_currency,
                    idToMarketplaceItem[_itemId - 1].salesProperty.expiresAt,
                    1
                );

                IERC721(idToMarketplaceItem[_itemId -1].nftContract).transferFrom(address(this), msg.sender, idToMarketplaceItem[_itemId - 1].tokenId);
                delete (idToMarketplaceItem[_itemId - 1]);
                

            } 
        else {
            revert("NFT does not meet the requirements to be taken off the market!");
        }
    }

    // query a sale status for an item
    function sellStatus(address nftcontract, uint tokenid) isWhitelisted(nftcontract) public view returns(bool) {
        uint256 _itemId = fetchItemId(nftcontract, tokenid);
        uint256 totalItemCount = idToMarketplaceItem.length;
        bool status;
        
        for (uint256 i = 0; i < totalItemCount; i++) {
            if(idToMarketplaceItem[i].itemId == _itemId){
                status = idToMarketplaceItem[i].sold;
            }
        }
        return status;
    } 

    function GrantRole(address _account) public onlyRole(DEFAULT_ADMIN_ROLE){
        // This is a function to make a wallet address to be able to be admin. 
        _grantRole(DEFAULT_ADMIN_ROLE,_account);
    }
    

}
