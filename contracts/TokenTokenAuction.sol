pragma solidity ^0.4.4;

/**
@title TokenInterface
@author https://codetract.io
@dev Standard functions of token.
*/
contract TokenInterface {
    function balanceOf(address _owner) constant returns(uint256 balance);
    function transfer(address _to, uint256 _value) returns(bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns(bool success);
}

/**
@title TokenTokenAuction
@author https://codetract.io
@dev Auction for tokens where all better orders settle at the same price provided there is enough volume.
*/
contract TokenTokenAuction {
    TokenInterface public tokenA;
    TokenInterface public tokenB;

    address[3] public owners;
    bool[3] public access;
    address public priceFeed;
    bool public halt;
    uint256 public haltTime;
    uint256 public tokenAmin;
    uint256 public tokenBmin;
    uint256 public tokenAfee;
    uint256 public tokenBfee;
    uint256 public divisor;

    struct order {
        address sender;
        uint256 price; //A/B=price, price of 0.2 means 1 B for 0.2 A, a higher price means B increased in value
        uint256 tokenARec;
        uint256 tokenBRec;
        uint256 tokenASent;
        uint256 tokenBSent;
        address returnAddress;
        uint256 session;
        uint8 valid; //0-default, 1-new order, 2-canceled, 3-settled filled, 4-settled partial filled, 5-settled no filled, 6-cancel error, 7-settled error
    }

    struct auctionPrice {
        uint256 price;
        uint256 markerSellB;
        uint256 partialSellB;
        uint256 highestSellB;
        uint256 markerBuyB;
        uint256 partialBuyB;
        uint256 lowestBuyB;
        uint256 block;
        bool seal;
    }

    mapping(uint256 => order) public ordersSellB;
    mapping(uint256 => order) public ordersBuyB;
    uint256 public indexSellB;
    uint256 public indexBuyB;
    mapping(uint256 => auctionPrice) public auctions;
    uint256 public currentSession;
    uint256 public endSession;
    uint8 public stage; //1-startTrading, 2-endSession, 3-auctionEnded/sealAuction

    /**
    @notice Initialises the values for the contract creation
    @dev Constructor, sets the tokens, owners and other specs.
    @param _tokenA Address of token A for trading
    @param _tokenB Address of token B for trading
    */
    function TokenTokenAuction(address _tokenA, address _tokenB) {
        tokenA = TokenInterface(_tokenA);
        tokenB = TokenInterface(_tokenB);

        owners[0] = 0x0;
        owners[1] = 0x0;
        owners[2] = 0x0;
        priceFeed = 0x0;
        halt = false;
        haltTime = now;
        tokenAmin = 0.1 ether;
        tokenBmin = 0.1 ether;
        tokenAfee = 0.01 ether;
        tokenBfee = 0.01 ether;
        divisor = 1000000000;

        indexSellB = 0;
        indexBuyB = 0;
        currentSession = 0;
        stage = 3;
    }

    /**
    @notice Simple 2 out of 3 access check
    */
    modifier accessGranted() {
        if(msg.sender == owners[0] || msg.sender == owners[1] || msg.sender == owners[2]) {
            if((access[0] && access[1]) || (access[0] && access[2]) || (access[1] && access[2])) {
                _;
            } else {
                throw;
            }
        } else {
            throw;
        }
    }
    modifier isPriceFeed() {
        if(priceFeed != msg.sender) {
            throw;
        }
        _;
    }
    modifier isNotHalt() {
        if(halt == true) {
            throw;
        }
        _;
    }
    modifier isHalt() {
        if(halt == false) {
            throw;
        }
        _;
    }
    modifier isStage1() {
        if(stage != 1) {
            throw;
        }
        _;
    }
    modifier isStage2() {
        if(stage != 2) {
            throw;
        }
        _;
    }
    modifier isStage3() {
        if(stage != 3) {
            throw;
        }
        _;
    }

    event OrderSellB(uint256 _indexSellB, address indexed _sender, uint256 _price, uint256 _tokenB);
    event OrderBuyB(uint256 _indexBuyB, address indexed _sender, uint256 _price, uint256 _tokenA);
    event CancelSellB(uint256 _indexSellB);
    event CancelBuyB(uint256 _indexBuyB);
    event AuctionEnded(
        uint256 _price,
        uint256 _markerSellB,
        uint256 _partialSellB,
        uint256 _highestSellB,
        uint256 _markerBuyB,
        uint256 _partialBuyB,
        uint256 _lowestBuyB,
        uint256 _block,
        bool _seal);
    event SettleSellB(uint256 _indexSellB, address indexed _returnAddress, uint256 _tokenA, uint256 _tokenB, uint8 _valid);
    event SettleBuyB(uint256 _indexBuyB, address indexed _returnAddress, uint256 _tokenA, uint256 _tokenB, uint8 _valid);

    /**
    @notice Create an order for selling B by sending B
    @dev Verify and store the order data which can be retrieved by its index from the OrderSellB event.
    @param _price Selling price of B with 9 decimal points e.g. web3.toWei(0.123456789, 'shannon')
    @param _tokenB Amount of B to sell
    @param _returnAddress Address the tokens will be sent to for canceling and after order is settled
    @return { "success": "order is created" }
    */
    function sellB(uint256 _price, uint256 _tokenB, address _returnAddress) isNotHalt isStage2 returns(bool success) {
        if(now > endSession) {
            stage = 3;
            return false;
        }
        if(_price == 0) {
            throw;
        }
        if(_tokenB < tokenBmin) {
            throw;
        }
        indexSellB++;
        if(tokenB.transferFrom(msg.sender, this, _tokenB)) {
            ordersSellB[indexSellB].sender = msg.sender;
            ordersSellB[indexSellB].price = _price;
            ordersSellB[indexSellB].tokenARec = 0; //_tokenB * _price
            ordersSellB[indexSellB].tokenBRec = _tokenB;
            ordersSellB[indexSellB].returnAddress = _returnAddress;
            ordersSellB[indexSellB].session = currentSession;
            ordersSellB[indexSellB].valid = 1;
            OrderSellB(indexSellB, ordersSellB[indexSellB].sender, ordersSellB[indexSellB].price, ordersSellB[indexSellB].tokenBRec);
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Create an order for buying B by sending A
    @dev Verify and store the order data which can be retrieved by its index from the OrderBuyB event.
    @param _price Buying price of B with 9 decimal points e.g. web3.toWei(0.123456789, 'shannon')
    @param _tokenA Amount of A to sell
    @param _returnAddress Address the tokens will be sent to for canceling and after order is settled
    @return { "success": "order is created" }
    */
    function buyB(uint256 _price, uint256 _tokenA, address _returnAddress) isNotHalt isStage2 returns(bool success) {
        if(now > endSession) {
            stage = 3;
            return false;
        }
        if(_price == 0) {
            throw;
        }
        if(_tokenA < tokenAmin) {
            throw;
        }
        indexBuyB++;
        if(tokenA.transferFrom(msg.sender, this, _tokenA)) {
            ordersBuyB[indexBuyB].sender = msg.sender;
            ordersBuyB[indexBuyB].price = _price;
            ordersBuyB[indexBuyB].tokenARec = _tokenA;
            ordersBuyB[indexBuyB].tokenBRec = 0; //_tokenA / _price
            ordersBuyB[indexBuyB].returnAddress = _returnAddress;
            ordersBuyB[indexBuyB].session = currentSession;
            ordersBuyB[indexBuyB].valid = 1;
            OrderBuyB(indexBuyB, ordersBuyB[indexBuyB].sender, ordersBuyB[indexBuyB].price, ordersBuyB[indexBuyB].tokenARec);
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Cancel a sell order and return the tokens
    @param _indexSellB The index of the sell order
    @return { "success": "order is canceled" }
    */
    function cancelSellB(uint256 _indexSellB) isNotHalt isStage2 returns(bool success) {
        if(now > endSession) {
            stage = 3;
            return false;
        }
        if(_indexSellB > indexSellB ||
            ordersSellB[_indexSellB].sender != msg.sender ||
            ordersSellB[_indexSellB].valid != 1 ||
            ordersSellB[_indexSellB].session != currentSession) {
            throw;
        }
        ordersSellB[_indexSellB].valid = 6;
        ordersSellB[_indexSellB].tokenBSent = ordersSellB[_indexSellB].tokenBRec;
        if(tokenB.transfer(ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenBSent)) {
            ordersSellB[_indexSellB].valid = 2;
            CancelSellB(_indexSellB);
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Cancel a buy order and return the tokens
    @param _indexBuyB The index of the buy order
    @return { "success": "order is canceled" }
    */
    function cancelBuyB(uint256 _indexBuyB) isNotHalt isStage2 returns(bool success) {
        if(now > endSession) {
            stage = 3;
            return false;
        }
        if(_indexBuyB > indexBuyB ||
            ordersBuyB[_indexBuyB].sender != msg.sender ||
            ordersBuyB[_indexBuyB].valid != 1 ||
            ordersBuyB[_indexBuyB].session != currentSession) {
            throw;
        }
        ordersBuyB[_indexBuyB].valid = 6;
        ordersBuyB[_indexBuyB].tokenASent = ordersBuyB[_indexBuyB].tokenARec;
        if(tokenA.transfer(ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenASent)) {
            ordersBuyB[_indexBuyB].valid = 2;
            CancelBuyB(_indexBuyB);
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Upload the settlement price after the auction has ended
    @dev The price and calculation are done off chain.
         With the 7 values, an order can be independently determined to be filled, partial filled or unfilled.
         In case of errors, the price can be uploaded again.
    @param _price [0] Price where all filled volume will transact at
                  [1] Index of the sell order that is partial filled
                  [2] B filled volume of the partial filled sell order
                  [3] Highest price among all the filled sell orders
                  [4] Index of the buy order that is partial filled
                  [5] B filled volume of the partial filled buy order
                  [6] Lowest price among all the filled buy orders
    @return { "success": "price is uploaded" }
    */
    function auctionEnded(uint256[7] _price) isPriceFeed isNotHalt isStage3 returns(bool success) {
        auctions[currentSession].price = _price[0];
        auctions[currentSession].markerSellB = _price[1];
        auctions[currentSession].partialSellB = _price[2];
        auctions[currentSession].highestSellB = _price[3];
        auctions[currentSession].markerBuyB = _price[4];
        auctions[currentSession].partialBuyB = _price[5];
        auctions[currentSession].lowestBuyB = _price[6];
        auctions[currentSession].block = block.number;
        AuctionEnded(auctions[currentSession].price,
            auctions[currentSession].markerSellB,
            auctions[currentSession].partialSellB,
            auctions[currentSession].highestSellB,
            auctions[currentSession].markerBuyB,
            auctions[currentSession].partialBuyB,
            auctions[currentSession].lowestBuyB,
            auctions[currentSession].block,
            auctions[currentSession].seal);
        return true;
    }

    /**
    @notice Confirm the uploaded price and prevent any more changes
    @dev The lag time mitigates the risk of a compromised priceFeed account.
    @return { "success": "price is sealed" }
    */
    function sealAuction() isPriceFeed isNotHalt isStage3 returns(bool success) {
        if(block.number > auctions[currentSession].block + 250 && auctions[currentSession].price > 0) {
            auctions[currentSession].seal = true;
            stage = 1;
            AuctionEnded(auctions[currentSession].price,
                auctions[currentSession].markerSellB,
                auctions[currentSession].partialSellB,
                auctions[currentSession].highestSellB,
                auctions[currentSession].markerBuyB,
                auctions[currentSession].partialBuyB,
                auctions[currentSession].lowestBuyB,
                auctions[currentSession].block,
                auctions[currentSession].seal);
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Set the end time of the next session and start to allow buy and sell orders
    @param _endSession Time in seconds to add to the last end time, usually this is just 86400
    @return { "success": "trading started" }
    */
    function startTrading(uint256 _endSession) isPriceFeed isNotHalt isStage1 returns(bool success) {
        endSession += _endSession;
        currentSession++;
        stage = 2;
        return true;
    }

    /**
    @notice Settle a sell order in a session whose price is sealed and get back the tokens
    @dev This can be called by anyone but there is a fee charged if this is called by the priceFeed account.
         Underflow is not checked as the uploaded price is assumed to be right.
    @param _indexSellB Index of the sell order
    @return { "success": "order is settled" }
    */
    function settleSellB(uint256 _indexSellB) isNotHalt returns(bool success) {
        if(_indexSellB > indexSellB ||
            ordersSellB[_indexSellB].valid != 1 ||
            auctions[ordersSellB[_indexSellB].session].seal != true) {
            throw;
        }
        ordersSellB[_indexSellB].valid = 7;
        if(auctions[ordersSellB[_indexSellB].session].highestSellB > 0) {
            if(_indexSellB == auctions[ordersSellB[_indexSellB].session].markerSellB) {
                ordersSellB[_indexSellB].tokenASent = auctions[ordersSellB[_indexSellB].session].partialSellB * auctions[ordersSellB[_indexSellB].session].price / divisor;
                ordersSellB[_indexSellB].tokenBSent = ordersSellB[_indexSellB].tokenBRec - auctions[ordersSellB[_indexSellB].session].partialSellB;
                ordersSellB[_indexSellB].valid = 4;
            } else if(ordersSellB[_indexSellB].price < auctions[ordersSellB[_indexSellB].session].highestSellB ||
                (ordersSellB[_indexSellB].price == auctions[ordersSellB[_indexSellB].session].highestSellB && _indexSellB < auctions[ordersSellB[_indexSellB].session].markerSellB) ||
                (ordersSellB[_indexSellB].price == auctions[ordersSellB[_indexSellB].session].highestSellB && auctions[ordersSellB[_indexSellB].session].partialSellB == 0)) {
                ordersSellB[_indexSellB].tokenASent = ordersSellB[_indexSellB].tokenBRec * auctions[ordersSellB[_indexSellB].session].price / divisor;
                ordersSellB[_indexSellB].valid = 3;
            } else {
                ordersSellB[_indexSellB].tokenBSent = ordersSellB[_indexSellB].tokenBRec;
                ordersSellB[_indexSellB].valid = 5;
            }
        } else {
            ordersSellB[_indexSellB].tokenBSent = ordersSellB[_indexSellB].tokenBRec;
            ordersSellB[_indexSellB].valid = 5;
        }
        if(ordersSellB[_indexSellB].tokenASent > 0) {
            if(msg.sender == priceFeed && ordersSellB[_indexSellB].tokenASent > tokenAfee) {
                if(!tokenA.transfer(priceFeed, tokenAfee)) {
                    throw;
                }
                if(!tokenA.transfer(ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenASent - tokenAfee)) {
                    throw;
                }
            } else {
                if(!tokenA.transfer(ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenASent)) {
                    throw;
                }
            }
        }
        if(ordersSellB[_indexSellB].tokenBSent > 0) {
            if(msg.sender == priceFeed && ordersSellB[_indexSellB].tokenBSent > tokenBfee) {
                if(!tokenB.transfer(priceFeed, tokenBfee)) {
                    throw;
                }
                if(!tokenB.transfer(ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenBSent - tokenBfee)) {
                    throw;
                }
            } else {
                if(!tokenB.transfer(ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenBSent)) {
                    throw;
                }
            }
        }
        SettleSellB(_indexSellB, ordersSellB[_indexSellB].returnAddress, ordersSellB[_indexSellB].tokenASent, ordersSellB[_indexSellB].tokenBSent, ordersSellB[_indexSellB].valid);
        return true;
    }

    /**
    @notice Settle a buy order in a session whose price is sealed and get back the tokens
    @dev This can be called by anyone but there is a fee charged if this is called by the priceFeed account for automatically settling orders.
         Underflow is not checked as the uploaded price is assumed to be right.
         1 wei of token A is burned for filled orders to prevent the case when tokenARec - a truncated amount.
    @param _indexBuyB Index of the buy order
    @return { "success": "order is settled" }
    */
    function settleBuyB(uint256 _indexBuyB) isNotHalt returns(bool success) {
        if(_indexBuyB > indexBuyB ||
            ordersBuyB[_indexBuyB].valid != 1 ||
            auctions[ordersBuyB[_indexBuyB].session].seal != true) {
            throw;
        }
        ordersBuyB[_indexBuyB].valid = 7;
        if(auctions[ordersBuyB[_indexBuyB].session].lowestBuyB > 0) {
            if(_indexBuyB == auctions[ordersBuyB[_indexBuyB].session].markerBuyB) {
                ordersBuyB[_indexBuyB].tokenASent = ordersBuyB[_indexBuyB].tokenARec - auctions[ordersBuyB[_indexBuyB].session].partialBuyB * auctions[ordersBuyB[_indexBuyB].session].price / divisor;
                ordersBuyB[_indexBuyB].tokenBSent = auctions[ordersBuyB[_indexBuyB].session].partialBuyB;
                ordersBuyB[_indexBuyB].valid = 4;
            } else if(ordersBuyB[_indexBuyB].price > auctions[ordersBuyB[_indexBuyB].session].lowestBuyB ||
                (ordersBuyB[_indexBuyB].price == auctions[ordersBuyB[_indexBuyB].session].lowestBuyB && _indexBuyB < auctions[ordersBuyB[_indexBuyB].session].markerBuyB) ||
                (ordersBuyB[_indexBuyB].price == auctions[ordersBuyB[_indexBuyB].session].lowestBuyB && auctions[ordersBuyB[_indexBuyB].session].partialBuyB == 0)) {
                ordersBuyB[_indexBuyB].tokenBSent = ordersBuyB[_indexBuyB].tokenARec * divisor / ordersBuyB[_indexBuyB].price;
                ordersBuyB[_indexBuyB].tokenASent = ordersBuyB[_indexBuyB].tokenARec - ordersBuyB[_indexBuyB].tokenARec * divisor / ordersBuyB[_indexBuyB].price * auctions[ordersBuyB[_indexBuyB].session].price / divisor;
                if(ordersBuyB[_indexBuyB].tokenASent >= 1) {
                    ordersBuyB[_indexBuyB].tokenASent -= 1;
                }
                ordersBuyB[_indexBuyB].valid = 3;
            } else {
                ordersBuyB[_indexBuyB].tokenASent = ordersBuyB[_indexBuyB].tokenARec;
                ordersBuyB[_indexBuyB].valid = 5;
            }
        } else {
            ordersBuyB[_indexBuyB].tokenASent = ordersBuyB[_indexBuyB].tokenARec;
            ordersBuyB[_indexBuyB].valid = 5;
        }
        if(ordersBuyB[_indexBuyB].tokenASent > 0) {
            if(msg.sender == priceFeed && ordersBuyB[_indexBuyB].tokenASent > tokenAfee) {
                if(!tokenA.transfer(priceFeed, tokenAfee)) {
                    throw;
                }
                if(!tokenA.transfer(ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenASent - tokenAfee)) {
                    throw;
                }
            } else {
                if(!tokenA.transfer(ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenASent)) {
                    throw;
                }
            }
        }
        if(ordersBuyB[_indexBuyB].tokenBSent > 0) {
            if(msg.sender == priceFeed && ordersBuyB[_indexBuyB].tokenBSent > tokenBfee) {
                if(!tokenB.transfer(priceFeed, tokenBfee)) {
                    throw;
                }
                if(!tokenB.transfer(ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenBSent - tokenBfee)) {
                    throw;
                }
            } else {
                if(!tokenB.transfer(ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenBSent)) {
                    throw;
                }
            }
        }
        SettleBuyB(_indexBuyB, ordersBuyB[_indexBuyB].returnAddress, ordersBuyB[_indexBuyB].tokenASent, ordersBuyB[_indexBuyB].tokenBSent, ordersBuyB[_indexBuyB].valid);
        return true;
    }

    /**
    @notice Halt the contract and prevent any non admin functions in an emergency
    @return { "success": "contract halted" }
    */
    function haltContract() accessGranted returns(bool success) {
        haltTime = now + 1 days;
        halt = true;
        return true;
    }

    /**
    @notice Unhalt the contract after at least a day have passed
    @return { "success": "contract unhalted" }
    */
    function unhaltContract() accessGranted returns(bool success) {
        if(now < haltTime) {
            throw;
        }
        halt = false;
        return true;
    }

    /**
    @notice Withdraw any mistakenly sent ether as this contract should not have any ether
    @return { "success": "ether withdrawn" }
    */
    function withdrawEth() accessGranted returns(bool success) {
        if(priceFeed.send(this.balance)) {
            return true;
        } else {
            throw;
        }
    }

    /**
    @notice Withdraw any mistakenly sent tokens but not A or B
    @param _token Token address
    @return { "success": "tokens withdrawn" }
    */
    function withdrawToken(address _token) accessGranted returns(bool success) {
        TokenInterface token = TokenInterface(_token);
        if(token != tokenA && token != tokenB) {
            if(token.transfer(priceFeed, token.balanceOf(this))) {
                return true;
            } else {
                throw;
            }
        } else {
            throw;
        }
    }

    /**
    @notice Change the account that can upload the price
    @param _priceFeed New address
    @return { "success": "priceFeed changed" }
    */
    function changePriceFeed(address _priceFeed) accessGranted returns(bool success) {
        priceFeed = _priceFeed;
        return true;
    }

    /**
    @notice Toggle the access flag for the owner
    @param _owner Index of the owner
    @return { "success": "access flag toggled" }
    */
    function grantAccess(uint8 _owner) returns(bool success) {
        if(msg.sender == owners[_owner]) {
            access[_owner] = !access[_owner];
        } else {
            throw;
        }
    }

    /**
    @notice Prevent not calling any functions
    */
    function() {
        throw;
    }

    /**
    @notice Constant function that checks the uploaded price
    @dev Performs a simulated settlement for all orders in the current session to ensure the uploaded price does not result in the contract having a shortage of tokens.
    @param _indexSellB Index of sell orders to start iterating from
    @param _indexBuyB Index of buy orders to start iterating from
    @return {
        "uint256[0]": "total A received for the session",
        "uint256[1]": "total A to be sent for the session",
        "uint256[2]": "any A remaining after settlement",
        "uint256[3]": "total B received for the session",
        "uint256[4]": "total B to be sent for the session",
        "uint256[5]": "any B remaining after settlement"
    }
    */
    function checkSettle(uint256 _indexSellB, uint256 _indexBuyB) returns(uint256[6]) {
        uint256 ARec = 0;
        uint256 BRec = 0;
        uint256 ASent = 0;
        uint256 BSent = 0;
        for(uint256 i = _indexSellB; i <= indexSellB; i++) {
            if(ordersSellB[i].valid == 1 && ordersSellB[i].session == currentSession) {
                BRec += ordersSellB[i].tokenBRec;
                if(auctions[currentSession].highestSellB > 0) {
                    if(i == auctions[currentSession].markerSellB) {
                        ASent += auctions[currentSession].partialSellB * auctions[currentSession].price / divisor;
                        BSent += ordersSellB[i].tokenBRec - auctions[currentSession].partialSellB;
                    } else if(ordersSellB[i].price < auctions[currentSession].highestSellB ||
                        (ordersSellB[i].price == auctions[currentSession].highestSellB && i < auctions[currentSession].markerSellB) ||
                        (ordersSellB[i].price == auctions[currentSession].highestSellB && auctions[currentSession].partialSellB == 0)) {
                        ASent += ordersSellB[i].tokenBRec * auctions[currentSession].price / divisor;
                    } else {
                        BSent += ordersSellB[i].tokenBRec;
                    }
                } else {
                    BSent += ordersSellB[i].tokenBRec;
                }
            }
        }
        for(uint256 k = _indexBuyB; k <= indexBuyB; k++) {
            if(ordersBuyB[k].valid == 1 && ordersBuyB[k].session == currentSession) {
                ARec += ordersBuyB[k].tokenARec;
                if(auctions[currentSession].lowestBuyB > 0) {
                    if(k == auctions[currentSession].markerBuyB) {
                        ASent += ordersBuyB[k].tokenARec - auctions[currentSession].partialBuyB * auctions[currentSession].price / divisor;
                        BSent += auctions[currentSession].partialBuyB;
                    } else if(ordersBuyB[k].price > auctions[currentSession].lowestBuyB ||
                        (ordersBuyB[k].price == auctions[currentSession].lowestBuyB && k < auctions[currentSession].markerBuyB) ||
                        (ordersBuyB[k].price == auctions[currentSession].lowestBuyB && auctions[currentSession].partialBuyB == 0)) {
                        BSent += ordersBuyB[k].tokenARec * divisor / ordersBuyB[k].price;
                        ASent += ordersBuyB[k].tokenARec - ordersBuyB[k].tokenARec * divisor / ordersBuyB[k].price * auctions[currentSession].price / divisor;
                        if(ASent >= 1) {
                            ASent -= 1;
                        }
                    } else {
                        ASent += ordersBuyB[k].tokenARec;
                    }
                } else {
                    ASent += ordersBuyB[k].tokenARec;
                }
            }
        }
        return [ARec, ASent, ARec - ASent, BRec, BSent, BRec - BSent];
    }
}
