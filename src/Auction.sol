// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "solmate/tokens/ERC20.sol";
import "./interfaces/IAMM.sol";
import "./libraries/Fenwick.sol";

uint256 constant timeout = 1 hours; // Time without bids for an auction to be finalized.

contract Auction {
    using Fenwick for mapping(uint256 => uint256);
    uint256 public reserve0;
    uint256 public reserve1;

    struct Surplus {
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

    Auction[] public auctions;
    mapping(uint256 => uint256) public surplus;
    IAMM public amm;
    bool public initialized;
    function initialize(IAMM _amm) external {
        require(!initialized, "Already initialized");
        amm = _amm;
        initialized = true;
    }

    function swap(uint amount0Out, uint amount1Out, address to) external {
        bool isBuy = amount1Out > 0;
        // amm is trusted not to re-enter
        amm.swap(amount0Out, amount1Out, address(this));
        uint256 delta = isBuy ? 
            ERC20(amm.token1()).balanceOf(address(this)) - reserve1 : 
            ERC20(amm.token0()).balanceOf(address(this)) - reserve0;
        auctions.push(Auction({
            outcome: isBuy ? delta : 0,
            price: isBuy ? 0 : delta,
            totalShares: amm.totalSupply(),
            lastTime: uint64(block.timestamp),
            winner: to,
            isBuy: amount1Out > 0
        }));
    }

    /// @dev Add liquidity.
    function addLiquidity() public payable {
        
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
