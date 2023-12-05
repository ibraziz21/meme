// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract NewToken is Context, Ownable, IERC20 {
    using SafeMath for uint256;

    event SwapAndLiquify(uint tokensAdded, uint EthAdded);
    event SwapAndSendOutTax(uint TokenAmount, uint NewBalance);

    //Variables
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;
    mapping(address => bool) private isNotTaxed;

    address payable private _taxWallet;
    address private uniswapV2Pair;
    IUniswapV2Router02 private uniswapV2Router;
    IUniswapV2Factory private factory;

    uint256 buyTax = 5;
    uint256 sellTax = 5;

    uint256 startTime;
    uint256 timeDeficit = 5 minutes;

    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 50000000000 * 10 **_decimals;
    string private _name = "Mambo Mtatu";
    string private _symbol = "Mattu";

    uint256 maxHoldPerWallet = 5000000000 * 10 ** _decimals;
    uint256 TaxSwapThreshold = 5000000000 * 10  ** _decimals;

    uint256 _totalBuys = 0;

    bool inSwap = false;

    constructor(address _Router) {
        address _deployer = _msgSender();
        _taxWallet = payable(_deployer);
        _balances[_deployer] = _totalSupply;
        isNotTaxed[_deployer] = true;
        isNotTaxed[address(this)] = true;

        uniswapV2Router = IUniswapV2Router02(_Router);
       


        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    modifier lockSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimal() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(
            from != address(0) || to != address(0),
            "Invalide From or To address"
        );
        require(amount != 0, "Invalid Amount");
        uint taxAmount = 0;

        if (from != owner() && to != owner()) {
            //IF A USER BUYS TOKENS FRO UNISWAPV2
            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !isNotTaxed[to]
            ) {
                taxAmount = amount.mul(buyTax).div(100);
                require(
                    balanceOf(to) + amount <= maxHoldPerWallet,
                    "Exceeds the Maximum Per Wallet."
                );

                _totalBuys++;
            }
            //IF ITS JUST TRANSFERRING TO ANOTHER WALLET
            if (to != uniswapV2Pair && !isNotTaxed[to]) {
                require(
                    balanceOf(to) + amount <= maxHoldPerWallet,
                    "Exceeds the maxWalletSize."
                );
            }
            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount.mul(sellTax).div(100);
            }

            //Get this contract's balance
            uint256 contractTokenBalance = balanceOf(address(this));
            //functions to send tax out
            if (
                !inSwap &&
                to == uniswapV2Pair &&
                contractTokenBalance > TaxSwapThreshold
            ) {
                uint halfTokens = TaxSwapThreshold.div(2);
                swapAndLiquify(halfTokens);
                swapAndSendOutTax(halfTokens);
            }
        }

        // If taxAmount is not 0, add it to the contract's balance
        if (taxAmount > 0) {
            _balances[address(this)] = _balances[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function swapAndSendOutTax(uint256 tokenAmount) private lockSwap {
        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint256 newBalance = address(this).balance - initialBalance;

        (bool sent, ) = (_taxWallet).call{value: newBalance}("");

        require(sent, "Eth not Sent");
        emit SwapAndSendOutTax(tokenAmount, newBalance);
    }

    function swapAndLiquify(uint256 tokens) private lockSwap {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint256 newBalance = address(this).balance - initialBalance;

        uniswapV2Router.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );

        emit SwapAndLiquify(half, newBalance);
    }

    function setUp() public {
         _approve(address(this), address(uniswapV2Router), _totalSupply);
            factory = IUniswapV2Factory(uniswapV2Router.factory());
            uniswapV2Pair = factory.createPair(address(this), uniswapV2Router.WETH());

            require(balanceOf(address(this)) > 0, "Insufficient token balance");
            require(address(this).balance > 0, "Insufficient ETH balance");

           uniswapV2Router.addLiquidityETH(
            address(this),
            balanceOf(address(this)),
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

    }
    receive() external payable {}
}
