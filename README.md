# tokenAuction

TokenAuction is an on chain auction on ethereum for tokens. This is similar to how stock exchanges determine the opening and closing prices of stocks where huge volumes can all transact at a single price. This is the first iteration of many of this smart contract. In this iteration we are focusing to ensure the settling mechanics work as expected to dispense the correct amount of tokens.

Some upcoming work:

- [X] UI https://auction.codetract.io
- [ ] better UI
- [ ] deploy to live net
- [ ] determine price base on on chain orders
- [ ] decentralize!

## Overview

The trading pair is ether (A) and augur reputation token (B). As only tokens are allowed, ether will need to be exchanged into ether tokens first. The price is quoted similar to that at poloniex.com where A/B=price and a price of 0.4 means you can buy 1 B with 0.4 A.   

The auction ends at 12:00 UTC everyday. Then the four hour (08:00 - 12:00) weighted average price from poloniex.com is taken as the settlement price. e.g. [api call](https://poloniex.com/public?command=returnChartData&currencyPair=ETH_REP&start=1479196800&end=1479196800&period=14400)

The computation to determine which orders are filled is done off chain and uploaded to the smart contract. Users can then settle their orders and receive their tokens. The next trading session will also start and users can create/cancel buy and sell orders till 12:00 UTC.

## For developers

#### Ropsten testnet

tokenA address: `0x8e97fbf72063b98fb4414be82107bbd3c35d4a55`  
tokenB address: `0x3ab9273fa791972d90809e26301d4eb0deea2ec6`  
token faucet: `0x85e15cd7c069c4367f6158a9480ffac6232c1df7`  
auction address: `0x1430064b130e4c5ba9cd032ce36818fc209313f9`

Send a 0 value transaction to the token faucet to receive free tokens A and B for use in the auction. Then `approve` the auction so that it can receive your tokenA and tokenB.

#### Functions

##### `sellB(uint256 _price, uint256 _tokenB, address _returnAddress)`

[TokenTokenAuction.sol:163-196](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L163-L196)

##### `buyB(uint256 _price, uint256 _tokenA, address _returnAddress)`

[TokenTokenAuction.sol:198-231](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L198-L231)

##### `cancelSellB(uint256 _indexSellB)`

[TokenTokenAuction.sol:233-258](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L233-L258)

##### `cancelBuyB(uint256 _indexBuyB)`

[TokenTokenAuction.sol:260-285](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L260-L285)

##### `settleSellB(uint256 _indexSellB)`

[TokenTokenAuction.sol:358-420](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L358-L420)

##### `settleBuyB(uint256 _indexBuyB)`

[TokenTokenAuction.sol:422-489](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L422-L489)
