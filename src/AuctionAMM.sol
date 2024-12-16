// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./interfaces/SimpleERC20.sol";
import "./libraries/Fenwick.sol";

uint256 constant timeout = 1 minutes; // Time without bids for an auction to be finalized.

contract AuctionAMM {
    using Fenwick for uint256[];

    struct LP {
        address payable owner;
        uint256 shares;
        uint256 start;
        uint256 end;
        uint256 withdrawnSurplus;
    }

    struct Auction {
        uint256 outcome; // Amount of outcome tokens.
        uint256 totalShares; // Amount of shares to split surplus.
        uint256 price; // Total price for those tokens.
        uint64 lastTime; // Time of the last bid.
        address payable winner; // The current winner of the auction.
        bool isBuy;
    }

    LP[] public LPs;
    Auction[] public auctions;
    uint256[] public surplus;

    uint256 public outcomeMax; // Maximum amount of outcome tokens to be sold.
    uint256 public outcome; // Amount of outcome tokens sold.
    uint256 public underlying; // Underlying collected as part of the AMM.
    uint256 public totalShares; // Total surplus collected.
    ERC20 public outcomeToken; // The outcome token traded.
    ERC20 public underlyingToken; // The underlying token traded.


    /// @dev Initialize the pool. Need to compute ofchain the amounts required.
    /// @param _outcome The amount of virtual outcome tokens sold.
    /// @param _outcomeMax The maximum amount of outcome tokens that can be sold.
    /// @param _outcomeToken The outcome token to be traded.
    /// @param _underlyingToken The underlying token to be traded.
    constructor(uint256 _outcome, uint256 _outcomeMax, ERC20 _outcomeToken, ERC20 _underlyingToken) payable {
        require(_outcome <= _outcomeMax); // Can't have sold more than the max.

        outcomeMax = _outcomeMax;
        outcome = _outcome;
        outcomeToken = _outcomeToken;
        require(outcomeToken.transferFrom(msg.sender, address(this), _outcomeMax - _outcome));

        underlyingToken = _underlyingToken;
        underlying = outcomeCost(_outcome, 0, _outcomeMax);
        require(underlyingToken.transferFrom(msg.sender, address(this), underlying));
    }

    function outcomeCost(uint256 _outcomeOut, uint256 _outcome, uint256 _outcomeMax) internal pure returns (uint256) {
        return (_outcomeOut * (_outcome + _outcomeOut/2)) / _outcomeMax;
    }

    /// @dev Buy outcome tokens.
    /// @param _outcomeOut Amount of outcome tokens to buy.
    function swapExactOutcomeForUnderlying(uint256 _outcomeOut) public payable {
        require(outcome + _outcomeOut <= outcomeMax); // Can't buy more than the max available.
        uint256 cost = outcomeCost(_outcomeOut, outcome, outcomeMax);
        underlying += cost;
        outcome += _outcomeOut;

        auctions.push(Auction({ // Create an auction.
            outcome: _outcomeOut,
            price: cost,
            totalShares: totalShares,
            lastTime: uint64(block.timestamp),
            winner: payable(msg.sender),
            isBuy: true
        }));

        require(underlyingToken.transferFrom(msg.sender, address(this), cost));
    }

    /// @dev Sell outcome tokens.
    /// @param _outcomeIn Amount of tokens to sell.
    function sell(uint256 _outcomeIn) public {
        require(outcomeToken.transferFrom(msg.sender, address(this), _outcomeIn));

        outcome -= _outcomeIn; // Note that it would revert if trying to sell more than possible.
        uint256 toReceive = outcomeCost(_outcomeIn, outcome, outcomeMax);
        underlying -= toReceive;
        auctions.push(Auction({ // Create a descending auction.
            outcome: _outcomeIn,
            price: toReceive,
            totalShares: totalShares,
            lastTime: uint64(block.timestamp),
            winner: payable(msg.sender),
            isBuy: false
        }));
        surplus.append(0);
    }

    /// @dev Add liquidity.
    function addLiquidity() public payable {
        uint256 oldUnderlying = underlying;
        uint256 newUnderlying = oldUnderlying + msg.value;
        uint256 newOutcomeMax = (outcomeMax * newUnderlying) / underlying;
        uint256 newOutcome = (outcome * newUnderlying) / underlying;
        uint256 outcomeIn =  (newOutcomeMax - newOutcome) - (outcomeMax - outcome);

        underlying = newUnderlying;
        outcomeMax = newOutcomeMax;
        outcome = newOutcome;

        uint256 mintShares = oldUnderlying > 0 ? msg.value * totalShares / oldUnderlying : newUnderlying;
        totalShares += mintShares;
        LPs.push(LP({
            owner: payable(msg.sender),
            shares: mintShares,
            start: auctions.length,
            end: 0,
            withdrawnSurplus: 0
        }));

        require(outcomeToken.transferFrom(msg.sender,address(this),outcomeIn));
    }

    /// @dev Remove liquidity.
    /// @param indexLP The index of the LP to remove.
    function removeLiquidity(uint256 indexLP) public payable {
        LP storage lp = LPs[indexLP];
        require(lp.end == 0, "Already removed");
        uint256 newUnderlying = (underlying * lp.shares) / totalShares;
        uint256 newOutcomeMax = (outcomeMax * lp.shares) / totalShares;
        uint256 newOutcome = (outcome * lp.shares) / totalShares;
        uint256 outcomeOut = outcome - newOutcome;

        lp.end = auctions.length;
        underlying = newUnderlying;
        outcome = newOutcome;
        outcomeMax = newOutcomeMax;

        require(outcomeToken.transfer(lp.owner, outcomeOut)); // Sent the outcome tokens removed.
        lp.owner.transfer(underlying - newUnderlying); // Send the underlying removed.
    }

    /// @dev Collect the bonus (tokens we got from overbiding in auctions)
    function collect(uint256 indexLP) public {
        LP storage lp = LPs[indexLP];
        uint256 surplusPerShare = surplus.rangeSum(lp.start, lp.end > 0 ? lp.end : auctions.length);
        uint256 bonus = surplusPerShare * lp.shares - lp.withdrawnSurplus;
        LPs[indexLP].withdrawnSurplus += bonus;
        require(underlyingToken.transfer(lp.owner, bonus), "Transfer failed");
    }

    /// @dev Bid in a buying auction.
    /// @param _auctionID The id of the buy auction.
    function buyBid(uint256 _auctionID) public payable {
        Auction storage auction = auctions[_auctionID];
        require(block.timestamp - auction.lastTime < timeout); // Make sure the auction is not over.
        surplus.increment(_auctionID, (msg.value - auction.price)/auction.totalShares);
        auction.winner.send(auction.price); // Reimburse the previous winner.
        auction.winner = payable(msg.sender);
        auction.price = msg.value;
        auction.lastTime = uint64(block.timestamp);
    }

    /// @dev Settle a buying auction.
    /// @param _auctionID The id of the buy auction.
    function buySettle(uint256 _auctionID) public {
        Auction storage auction = auctions[_auctionID];
        require(block.timestamp - auction.lastTime >= timeout); // Make sure the auction is over.
        
        uint256 outcomeOut = auction.outcome;
        auction.outcome = 0;
        require(outcomeToken.transfer(auction.winner, outcomeOut));
    }

    /// @dev Bid in a selling auction.
    /// @param _auctionID The id of the sell auction.
    /// @param _price The price to accept. It should be lower than the current price.
    function sellBid(uint256 _auctionID, uint256 _price) public {
        Auction storage auction = auctions[_auctionID];
        require(block.timestamp - auction.lastTime < timeout); // Make sure the auction is not over.

        surplus.increment(_auctionID, (auction.price - _price)/auction.totalShares);
        require(outcomeToken.transferFrom(msg.sender, auction.winner, auction.outcome)); // Send the outcome tokens of the current winner to the previous one.
        auction.winner = payable(msg.sender);
        auction.price = _price;
        auction.lastTime = uint64(block.timestamp);
    }

    /// @dev Settle a selling auction.
    /// @param _auctionID The id of the buy auction.
    function sellSettle(uint256 _auctionID) public {
        Auction storage auction = auctions[_auctionID];
        require(block.timestamp - auction.lastTime >= timeout); // Make sure the auction is over.
        
        uint256 underlyingOut = auction.price;
        auction.price = 0;
        auction.winner.transfer(underlyingOut); // Pay the winner.
    }


    ////// Helpers ////////
    function requiredAmountBuy(uint256 _outcomeOut) public view returns (uint256 underlyingIn) {
        require(outcome + _outcomeOut <= outcomeMax); // Can't buy more than the max available.
        underlyingIn = (_outcomeOut * (outcome + _outcomeOut/2)) / outcomeMax;
    }

    function sellPrice(uint256 _outcomeIn) view public returns(uint256 toReceive) {
        uint256 _outcome = outcome - _outcomeIn;
        toReceive = (_outcomeIn * (_outcome + _outcomeIn/2) ) / outcomeMax;
    }

    function requiredOutcomeForAdd(uint256 _underlyingToAdd) view public returns(uint256 outcomeIn) {
        uint256 newUnderlying = underlying + _underlyingToAdd;
        uint256 newOutcomeMax = (outcomeMax * newUnderlying) / underlying;
        uint256 newOutcome = (outcome * newUnderlying) / underlying;
        outcomeIn =  (newOutcomeMax - newOutcome) - (outcomeMax - outcome);
    }

    function requiredAmountInit(uint256 _outcome, uint256 _outcomeMax) public pure returns (uint256 underlying, uint256 outcome) {
        require(_outcome <= _outcomeMax); // Can't have sold more than the max.
        underlying = (_outcome * _outcome ) / (2 * _outcomeMax);
        outcome = _outcomeMax - _outcome;
    }
}
