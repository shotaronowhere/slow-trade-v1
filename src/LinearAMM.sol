// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./utils/SimpleERC20.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";

contract LinearAMM is SimpleERC20 {
    struct LP {
        address payable owner;
        uint256 shares;
    }

    LP[] public LPs;
    uint256 public outcomeMax; // Maximum amount of outcome tokens to be sold.
    uint256 public outcome; // Amount of outcome tokens sold.
    uint256 public totalSupply; // Total amount of shares minted.
    uint256 public underlying; // Underlying collected as part of the AMM.
    ERC20 public outcomeToken; // The outcome token traded.
    ERC20 public underlyingToken; // The underlying token traded.
    address public owner;

    modifier onlyOwner() {
        require(owner == address(0) || msg.sender == owner, "Only owner can call this function");
        _;
    }

    /// @dev Initialize the pool.
    /// @param _outcomeToken The outcome token to be traded.
    /// @param _underlyingToken The underlying token to be traded.
    constructor(ERC20 _outcomeToken, ERC20 _underlyingToken) payable {
        outcomeToken = _outcomeToken;
        underlyingToken = _underlyingToken;
        owner = msg.sender;
    }

    /// @dev Buy outcome tokens.
    /// @param _outcomeOut Amount of outcome tokens to buy.
    function buy(uint256 _outcomeOut) public onlyOwner {
        require(outcome + _outcomeOut <= outcomeMax); // Can't buy more than the max available.
        uint256 cost = outcomeCost(_outcomeOut, outcome, outcomeMax);
        underlying += cost;
        outcome += _outcomeOut;

        require(outcomeToken.transfer(msg.sender, _outcomeOut));
        require(underlyingToken.transferFrom(msg.sender, address(this), cost));
    }

    /// @dev Sell outcome tokens.
    /// @param _outcomeIn Amount of tokens to sell.
    function sell(uint256 _outcomeIn) public onlyOwner {
        require(outcomeToken.transferFrom(msg.sender, address(this), _outcomeIn));

        outcome -= _outcomeIn; // Note that it would revert if trying to sell more than possible.
        uint256 toReceive = outcomeCost(_outcomeIn, outcome, outcomeMax);
        underlying -= toReceive;
    }

    /// @dev Add liquidity.
    function addLiquidity(uint256 _underlyingToAdd) public payable {
        uint256 oldUnderlying = underlying;
        uint256 newUnderlying = oldUnderlying + _underlyingToAdd;
        uint256 newOutcomeMax = (outcomeMax * newUnderlying) / underlying;
        uint256 newOutcome = (outcome * newUnderlying) / underlying;
        uint256 outcomeIn =  (newOutcomeMax - newOutcome) - (outcomeMax - outcome);

        underlying = newUnderlying;
        outcomeMax = newOutcomeMax;
        outcome = newOutcome;

        uint256 liquidity;
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = _underlyingToAdd + outcomeIn  + Math.sqrt(_underlyingToAdd * (_underlyingToAdd + 2 * outcomeIn) );
        } else {
            liquidity = _underlyingToAdd / underlying;
        }

        totalSupply += liquidity;
        LPs.push(LP({
            owner: payable(msg.sender),
            shares: liquidity
        }));

        require(outcomeToken.transferFrom(msg.sender,address(this),outcomeIn));
        require(underlyingToken.transferFrom(msg.sender, address(this), _underlyingToAdd));
    }

    /// @dev Remove liquidity.
    /// @param indexLP The index of the LP to remove.
    function removeLiquidity(uint256 indexLP) public payable {
        LP storage lp = LPs[indexLP];
        require(!lp.removed, "Already removed");
        lp.removed = true;
        uint256 newUnderlying = (underlying * lp.shares) / totalSupply;
        uint256 newOutcomeMax = (outcomeMax * lp.shares) / totalSupply;
        uint256 newOutcome = (outcome * lp.shares) / totalSupply;
        uint256 outcomeOut = outcome - newOutcome;

        uint256 underlyingOut = underlying - newUnderlying;
        underlying = newUnderlying;
        outcome = newOutcome;
        outcomeMax = newOutcomeMax;

        require(outcomeToken.transfer(lp.owner, outcomeOut)); // Sent the outcome tokens removed.
        require(underlyingToken.transfer(lp.owner, underlyingOut)); // Send the underlying removed.
    }

    function outcomeCost(uint256 _outcomeOut, uint256 _outcome, uint256 _outcomeMax) internal pure returns (uint256) {
        return (_outcomeOut * (_outcome + _outcomeOut/2)) / _outcomeMax;
    }
}
