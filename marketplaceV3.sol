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


    uint256 listingPrice = 0.025 ether; // minimum price, change for what you want
    uint256 DEFAULT_DURATION = 60 days;

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
        uint256 MarketVersion
    );

    event MarketplaceItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        uint256 MarketVersion

    );

    event ItemPriceUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        uint256 MarketVersion
    );

    event ItemFroyoPriceUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 froyoprice,
        uint256 MarketVersion
    );

    event ItemSalesDuration(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 startAt,
        uint256 expiredAt,
        uint256 MarketVersion
    );


    constructor(address _froyoContract) payable {
        owner = payable(msg.sender);
        froyoContract = _froyoContract;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    
    function setFroyoAddress(address _froyo) public onlyRole(DEFAULT_ADMIN_ROLE) {
        froyoContract = _froyo;
    }

    function setMarketToggle(bool _stopMarket) public onlyRole(DEFAULT_ADMIN_ROLE) {
        marketPlaceToggle = _stopMarket;
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
    }

    // returns the listing price of the contract
    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    // verify whitelist nft contracts 
    function verifyUser(address _whitelistedAddress) public view returns(bool) {
        bool userIsWhitelisted = whitelistedAddresses[_whitelistedAddress];
        return userIsWhitelisted;
    }


    // set listing price of the contract
    function setCost(uint256 _newCost) public onlyRole(DEFAULT_ADMIN_ROLE) {
        listingPrice = _newCost;
    }
    
    // places an item for sale on the marketplace
    // the seller must put a price for both currency(native + froyo)
    function CreateItemFixedPriceSales(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 isFroyo,
        uint256 _duration
    ) external payable isWhitelisted(nftContract)  MarketPlaceToggle nonReentrant {
        require(price > 0, "Price cannot be 0");
        require(
            msg.value == listingPrice,
            "Price must be equal to listing price"
        );
        
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

        payable(owner).transfer(listingPrice);
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

        payable(owner).transfer(listingPrice);
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
        address myItemAddrs = idToMarketplaceItem[_itemid -1].nftContract;
        uint256 myTokenID = idToMarketplaceItem[_itemid -1].tokenId;

        return (myItemAddrs,myTokenID);
    }
    
    //fetch BNB price of marketplace item  
    function fetchItemPriceFroyo(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
        require(idToMarketplaceItem[myItemid -1].price == 0, "The item does not accept BNB currency!");

        return idToMarketplaceItem[myItemid -1].froyoPrice;
    }

    function fetchItemPriceBNB(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
        require(idToMarketplaceItem[myItemid -1].froyoPrice == 0, "The item does not accept Froyo currency!");

        return idToMarketplaceItem[myItemid -1].price;
    }

    function getExpiredDate(address _nftcontract, uint _tokenid) isWhitelisted(_nftcontract) public view returns (uint) {
        uint myItemid = fetchItemId(_nftcontract,_tokenid);
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
        payable
        nonReentrant
    {
        uint256 itemId = fetchItemId(_nftContract, _tokenId);
        uint256 price = idToMarketplaceItem[itemId - 1].froyoPrice;
        uint256 tokenId = idToMarketplaceItem[itemId - 1].tokenId;
        address seller = idToMarketplaceItem[itemId -1].seller;
        uint256 expiredSale = idToMarketplaceItem[itemId - 1].salesProperty.expiresAt;
        uint256 currentBalance = IERC20(froyoContract).balanceOf(msg.sender);
        
        /*
         * Price already uses wei unit
         */
        uint256 froyoamount = price;
        require(idToMarketplaceItem[itemId - 1].sold == false, "The item is already sold!");
        require(
            currentBalance >= froyoamount,
            "Insufficient balance, please buy more FROYO in order to complete the purchase"
        );
        require(block.timestamp < expiredSale, "This sales has ended");
        require(idToMarketplaceItem[itemId -1].price == 0 ,"This item does not accept Froyo currency!");
        IERC20(froyoContract).transferFrom(msg.sender,seller,froyoamount); 
        IERC721(_nftContract).transferFrom(address(this), msg.sender, tokenId);
        idToMarketplaceItem[itemId - 1].owner = payable(msg.sender);
        idToMarketplaceItem[itemId - 1].sold = true;
        

        emit MarketplaceItemSold(
        itemId,
        _nftContract,
        tokenId,
        idToMarketplaceItem[itemId - 1].seller,
        idToMarketplaceItem[itemId - 1].owner,
        idToMarketplaceItem[itemId - 1].froyoPrice,
        idToMarketplaceItem[itemId - 1].sold,
        1
        );
        
        _soldItems.increment();


    }

    function BuyNftFixedPriceSales(address _nftContract , uint _tokenId) 
        isWhitelisted(_nftContract)
        public 
        payable 
        nonReentrant 
    {
        uint256 _itemId = fetchItemId(_nftContract, _tokenId);
        uint256 price = idToMarketplaceItem[_itemId - 1].price;
        uint256 tokenId = idToMarketplaceItem[_itemId - 1].tokenId;
        uint256 expiredSale = idToMarketplaceItem[_itemId - 1].salesProperty.expiresAt;
        uint256 salestyp = idToMarketplaceItem[_itemId - 1].salesProperty.salesType;
        require(idToMarketplaceItem[_itemId - 1].sold == false, "The item is already sold!");
        require(salestyp == 1, "This item is not a fixed price sales!");
        require(block.timestamp < expiredSale, "This sales has ended");
        require(idToMarketplaceItem[_itemId -1].froyoPrice == 0 ,"The item does not accept BNB currency!");
        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );
        
        idToMarketplaceItem[_itemId - 1].owner = payable(msg.sender);
        idToMarketplaceItem[_itemId - 1].sold = true;
        

        emit MarketplaceItemSold(
        _itemId,
        _nftContract,
        tokenId,
        idToMarketplaceItem[_itemId - 1].seller,
        idToMarketplaceItem[_itemId - 1].owner,
        idToMarketplaceItem[_itemId - 1].price,
        idToMarketplaceItem[_itemId - 1].sold,
        1
        );

       
        IERC721(_nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        payable(idToMarketplaceItem[_itemId - 1].seller).transfer(msg.value);

        _soldItems.increment();

    }

    function ChangeNftPriceFixedSales(address _nftcontract, uint _tokenid, uint _newprice) isWhitelisted(_nftcontract) public {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");
         require(idToMarketplaceItem[_itemid -1].froyoPrice == 0 ,"The item does not accept BNB currency!");
        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        
        emit ItemPriceUpdated(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        _newprice,
        1
        );

        idToMarketplaceItem[_itemid - 1].price = _newprice;

    }

    function ChangeNftPriceFixedSalesFroyo(address _nftcontract, uint _tokenid, uint _newprice) isWhitelisted(_nftcontract) public {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");
        require(idToMarketplaceItem[_itemid -1].price == 0 ,"This item does not accept Froyo currency!");
        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        
        emit ItemFroyoPriceUpdated(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        _newprice,
        1
        );

        idToMarketplaceItem[_itemid - 1].froyoPrice = _newprice;

    }


    function ChangeNftSalesDuration(address _nftcontract, uint _tokenid, uint _salesDuration) MarketPlaceToggle isWhitelisted(_nftcontract) public payable {
        uint256 _itemid = fetchItemId(_nftcontract, _tokenid);
        require(msg.value == listingPrice , "You are require to pay the listing fees!");
        // require(idToMarketplaceItem[_itemid -1].salesProperty.salesType == 1, "Applicable only for fixed price sales");
        require(idToMarketplaceItem[_itemid - 1].seller == msg.sender, "You are not the owner");
        require(idToMarketplaceItem[_itemid - 1].isListed == true, "You have yet to list any item!");

        uint256 expiredSale = idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt;
        require(block.timestamp < expiredSale, "This sales has ended");
        

        uint256 numberOfdays;
        numberOfdays = (_salesDuration * 1 days);
        idToMarketplaceItem[_itemid - 1].salesProperty.startAt = block.timestamp;
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt = block.timestamp + numberOfdays;

        emit ItemSalesDuration(
        idToMarketplaceItem[_itemid - 1].seller,
        idToMarketplaceItem[_itemid - 1].nftContract,
        idToMarketplaceItem[_itemid - 1].tokenId,
        idToMarketplaceItem[_itemid - 1].salesProperty.startAt,
        idToMarketplaceItem[_itemid - 1].salesProperty.expiresAt,
        1 
        );
        
        payable(owner).transfer(listingPrice);

    }


    // fetch all marketplace items
    // return a tuple 
    function getAllActiveListedItems()
        public
        view
        returns (MarketplaceItem[] memory)
    {
        uint myLength = idToMarketplaceItem.length;
        
        MarketplaceItem[] memory nfts = new MarketplaceItem[](myLength);
        uint nftsIndex = 0;
        for (uint i = 0; i < myLength; i++) {
            nfts[nftsIndex] = idToMarketplaceItem[i];
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
        require(idToMarketplaceItem[_itemId - 1].seller == msg.sender, "You are not the owner!");
        address NFTcontract;
        uint token_id; 
        uint myLen = idToMarketplaceItem.length;
        bool result = false;
        uint currentindex;
        uint256 myitem = _items.current();
        
        if(myitem == _itemId) {
            emit MarketplaceItemCanceled(
            _itemId,
            idToMarketplaceItem[_itemId -1].nftContract,
            idToMarketplaceItem[_itemId - 1].tokenId,
            msg.sender,
            1
            );
            
            _items.decrement();
            IERC721(idToMarketplaceItem[_itemId -1].nftContract).transferFrom(address(this), msg.sender, idToMarketplaceItem[_itemId - 1].tokenId);
            idToMarketplaceItem.pop();
            
        }
        else {

            for (uint256 i = 0; i < myLen; i++) {
                if 
                (idToMarketplaceItem[i].seller == msg.sender && 
                idToMarketplaceItem[i].sold == false &&
                 idToMarketplaceItem[i].itemId == _itemId && 
                idToMarketplaceItem[i].isListed == true
                ) 
                {  
                NFTcontract = idToMarketplaceItem[i].nftContract;
                token_id = idToMarketplaceItem[i].tokenId;

                IERC721(NFTcontract).transferFrom(address(this), msg.sender, token_id);

                idToMarketplaceItem[i] = idToMarketplaceItem[myLen - 1];
                idToMarketplaceItem[myLen - 1] = idToMarketplaceItem[i];
                result = true;
                currentindex = i;
                }
            }

            if(result == true) {
            
                emit MarketplaceItemCanceled(
                _itemId,
                NFTcontract,
                token_id,
                msg.sender,
                1
                );
            
                idToMarketplaceItem[currentindex].itemId = _itemId;
                _items.decrement();
                idToMarketplaceItem.pop();
            }
             else{
            revert("NFT does not meet the requirements to be taken off the market!");
            }

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
