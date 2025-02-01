// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "solmate/tokens/ERC20.sol";
    
contract Linear is ERC20 {
    /// @dev Flag to initialize the market only once.
    bool public initialized;

    uint256 public reserve0;
    uint256 public reserve1;
    ERC20 public token0; // The outcome token traded.
    ERC20 public token1; // The underlying token traded.
    
    address public immutable owner;
    uint256 public immutable FEE_BASIS_POINTS;
    uint256 public constant BASIS = 10000;

    uint public constant MINIMUM_LIQUIDITY = 10**3;

    modifier onlyOwner() {
        require(owner == address(0) || msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(uint256 _feeBasisPoints, address _owner) ERC20("Slowtrade-V1", "STD", 18) payable {
        FEE_BASIS_POINTS = _feeBasisPoints;
        owner = _owner;
    }

    function initialize(ERC20 _token0, ERC20 _token1) external onlyOwner {
        require(!initialized, "Already initialized");
        require(address(_token0) != address(0) && address(_token1) != address(0), "Invalid token");
        token0 = _token0;
        token1 = _token1;
        initialized = true;
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to) external onlyOwner {
        require(amount0Out > 0 || amount1Out > 0, "No tokens to swap");
        
        uint256 balance0 = token0.balanceOf(address(this)) - amount0Out;
        uint256 balance1 = token1.balanceOf(address(this)) - amount1Out;

        uint amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Slowtrade: INSUFFICIENT_INPUT_AMOUNT');

        uint balance0Adjusted = balance0 * BASIS - amount0In * FEE_BASIS_POINTS;
        uint balance1Adjusted = balance1 * BASIS - amount1In * FEE_BASIS_POINTS;
        require(k(balance0Adjusted, balance1Adjusted) >= BASIS * k(reserve0, reserve1), 'Slowtrade: K');

        reserve0 = balance0;
        reserve1 = balance1;

        if (amount0Out > 0) token0.transfer(to, amount0Out);
        if (amount1Out > 0) token1.transfer(to, amount1Out);
        //emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function k(uint256 x, uint256 y) internal pure returns (uint256) {
        return x + y + Math.sqrt(x * (x+2*y));
    }

    /// @dev Add liquidity.
    function mint(address to) public onlyOwner {
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));
        uint amount0 = balance0 - reserve0;
        uint amount1 = balance1 - reserve1;
        uint liquidity;
        if (totalSupply == 0) {
            liquidity = k(amount0,amount1) - MINIMUM_LIQUIDITY;
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            if (reserve0 == 0) {
                liquidity = amount1*totalSupply / reserve1;
            } else if (reserve1 == 0) {
                liquidity = amount0*totalSupply / reserve0;
            } else {
                liquidity = Math.min(amount0*totalSupply / reserve0, amount1*totalSupply / reserve1);
            }
        }
        require(liquidity > 0, 'Slowtrade: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        reserve0 = balance0;
        reserve1 = balance1;
        //emit Mint(msg.sender, amount0, amount1);
    }

    /// @dev Remove liquidity.
    function burn(address to) public onlyOwner {
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint256 amount0 = liquidity * balance0 / totalSupply; // using balances ensures pro-rata distribution
        uint256 amount1 = liquidity * balance1 / totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Slowtrade: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);

        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        token0.transfer(to, amount0);
        token1.transfer(to, amount1);
        //emit Burn(msg.sender, amount0, amount1, to);
    }
}

library Math {
    /**
     * @dev Calculates the square root of a number. Uses the Babylonian Method.
     * @param x The input.
     * @return y The square root of the input.
     **/
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
