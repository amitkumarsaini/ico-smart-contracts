//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/ReentrancyGuard.sol";
import "./libraries/TransferHelper.sol";
import "./utils/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/OracleWrapper.sol";
import "hardhat/console.sol";

contract CHBPublicSale is Ownable, ReentrancyGuard {
    uint256 public totalTokenSold;
    uint256 public totalUSDTRaised;
    uint256 public tokenDecimal;
    uint8 public defaultPhase;
    uint8 public totalPhases;
    address public tokenAddress;
    address public USDTAddress;
    address public USDTOracleAddress;
    address public BNBorETHOracleAddress;
    address public receiverAddress;

    /* ================ STRUCT SECTION ================ */
    // Stores phases
    struct Phases {
        uint256 tokenSold;
        uint256 tokenLimit;
        uint32 startTime;
        uint32 expirationTimestamp;
        uint32 price; // 10 ** 2
        bool isComplete;
    }
    mapping(uint256 => Phases) public phaseInfo;

    /* ================ EVENT SECTION ================ */
    // Emits when tokens are bought
    event TokensBought(
        address buyerAddress,
        uint256 buyAmount,
        uint256 tokenAmount,
        uint32 buyTime
    );

    /* ================ CONSTRUCTOR SECTION ================ */
    constructor(
        address _tokenAddress,
        address _usdtAddress,
        address _usdtOracleAddress,
        address _BNBorETHOracleAddress
    ) {
        tokenAddress = _tokenAddress;
        USDTAddress = _usdtAddress;
        USDTOracleAddress = _usdtOracleAddress;
        BNBorETHOracleAddress = _BNBorETHOracleAddress;

        totalPhases = 6;
        defaultPhase = 0;
        tokenDecimal = uint256(10**Token(tokenAddress).decimals());
        uint32 currenTimeStamp = uint32(block.timestamp);

        phaseInfo[0] = Phases({
            tokenLimit: 200_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: currenTimeStamp,
            expirationTimestamp: currenTimeStamp + 3 minutes, // 2 Months
            price: 1,
            isComplete: false
        });
        phaseInfo[1] = Phases({
            tokenLimit: 100_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: phaseInfo[0].expirationTimestamp,
            expirationTimestamp: phaseInfo[0].expirationTimestamp + 3 minutes, // 15 Days
            isComplete: false,
            price: 2
        });
        phaseInfo[2] = Phases({
            tokenLimit: 100_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: phaseInfo[1].expirationTimestamp,
            expirationTimestamp: phaseInfo[1].expirationTimestamp + 3 minutes, // 15 Days
            isComplete: false,
            price: 3
        });
        phaseInfo[3] = Phases({
            tokenLimit: 100_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: phaseInfo[2].expirationTimestamp,
            expirationTimestamp: phaseInfo[2].expirationTimestamp + 3 minutes, // 15 Days
            isComplete: false,
            price: 4
        });
        phaseInfo[4] = Phases({
            tokenLimit: 100_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: phaseInfo[3].expirationTimestamp,
            expirationTimestamp: phaseInfo[3].expirationTimestamp + 3 minutes, // 15 Days
            isComplete: false,
            price: 5
        });
        phaseInfo[5] = Phases({
            tokenLimit: 100_000_000 * tokenDecimal,
            tokenSold: 0,
            startTime: phaseInfo[4].expirationTimestamp,
            expirationTimestamp: phaseInfo[4].expirationTimestamp + 3 minutes, // 15 Days
            isComplete: false,
            price: 6
        });
    }

    /* ================ BUYING TOKENS SECTION ================ */

    // Receive Function
    receive() external payable {
        // Sending deposited currency to the receiver address
        payable(receiverAddress).transfer(msg.value);
    }

    // Function lets user buy CHB tokens || Type 1 = BNB or ETH, Type = 2 for USDT
    function buyTokens(uint8 _type, uint256 _usdtAmount)
        external
        payable
        nonReentrant
    {
        require(
            block.timestamp < phaseInfo[5].expirationTimestamp,
            "Buying Phases are over"
        );

        uint256 _buyAmount;

        // If type == 1
        if (_type == 1) {
            _buyAmount = msg.value;

            // Sending deposited currency to the receiver address
            payable(receiverAddress).transfer(_buyAmount);
        }
        // If type == 2
        else {
            _buyAmount = _usdtAmount;

            // Balance Check
            require(
                Token(USDTAddress).balanceOf(msg.sender) >= _buyAmount,
                "User doesn't have enough balance"
            );

            // Allowance Check
            require(
                Token(USDTAddress).allowance(msg.sender, address(this)) >=
                    _buyAmount,
                "Allowance provided is low"
            );

            // Sending deposited currency to the receiver address
            TransferHelper.safeTransferFrom(
                USDTAddress,
                msg.sender,
                receiverAddress,
                _buyAmount
            );
        }

        // Token calculation
        (uint256 _tokenAmount, uint8 _phaseNo) = calculateTokens(
            _type,
            _buyAmount
        );

        // Phase info setting
        setPhaseInfo(_tokenAmount, defaultPhase);

        // Transfers CHB to user
        TransferHelper.safeTransfer(tokenAddress, msg.sender, _tokenAmount);

        // Update Phase number and add token amount
        defaultPhase = _phaseNo;
        totalTokenSold += _tokenAmount;

        // Calculated total USDT raised in the platform
        (uint256 _amountToUSD, uint256 _typeDecimal) = cryptoValues(_type);
        totalUSDTRaised += uint256((_buyAmount * _amountToUSD) / _typeDecimal);

        // Emits event
        emit TokensBought(
            msg.sender,
            _buyAmount,
            _tokenAmount,
            uint32(block.timestamp)
        );
    }

    // Function calculates tokens according to user's given amount
    function calculateTokens(uint8 _type, uint256 _amount)
        public
        view
        returns (uint256, uint8)
    {
        return calculateTokensInternal(_type, _amount, defaultPhase, 0);
    }

    // Internal function to calculatye tokens
    function calculateTokensInternal(
        uint8 _type,
        uint256 _amount,
        uint8 _phaseNo,
        uint256 _previousTokens
    ) internal view returns (uint256, uint8) {
        // Phases cannot exceed totalPhases
        require(
            _phaseNo < totalPhases,
            "Not enough tokens in the contract or Phase expired"
        );

        Phases memory pInfo = phaseInfo[_phaseNo];

        // If phase is still going on
        if (pInfo.expirationTimestamp > block.timestamp) {
            uint256 _tokensAmount = tokensUserWillGet(
                _type,
                _amount,
                pInfo.price
            );

            uint256 _tokensLeftToSell = (pInfo.tokenLimit + _previousTokens) -
                pInfo.tokenSold;

            // If token left are 0. Next phase will be executed
            if (_tokensLeftToSell == 0) {
                return
                    calculateTokensInternal(
                        _type,
                        _amount,
                        _phaseNo + 1,
                        _previousTokens
                    );
            }
            // If the phase have enough tokens left
            else if (_tokensLeftToSell >= _tokensAmount) {
                return (_tokensAmount, _phaseNo);
            }
            // If the phase doesn't have enough tokens
            else {
                // Tokens that couldn't be brought
                uint256 _tokensLeft = _tokensAmount -
                    (pInfo.tokenLimit + _previousTokens - pInfo.tokenSold);
                _tokensAmount -= _tokensLeft;

                // Amount in crypto left
                (uint256 _amountToUSD, uint256 _typeDecimal) = cryptoValues(
                    _type
                );
                uint256 amountInCryptoLeft = (_tokensLeft *
                    pInfo.price *
                    _typeDecimal *
                    (10**8)) / (_amountToUSD * tokenDecimal * 100);

                (
                    uint256 remainingTokens,
                    uint8 newPhase
                ) = calculateTokensInternal(
                        _type,
                        amountInCryptoLeft,
                        _phaseNo + 1,
                        _previousTokens
                    );

                return (remainingTokens + _tokensAmount, newPhase);
            }
        }
        // In case the phase is expired. New will begin after sending the left tokens to the next phase
        else {
            uint256 _remainingTokens = pInfo.tokenLimit - pInfo.tokenSold;
            return
                calculateTokensInternal(
                    _type,
                    _amount,
                    _phaseNo + 1,
                    _remainingTokens + _previousTokens
                );
        }
    }

    // Tokens user will get according to the price
    function tokensUserWillGet(
        uint8 _type,
        uint256 _amount,
        uint32 _price
    ) public view returns (uint256) {
        (uint256 _amountToUSD, uint256 _typeDecimal) = cryptoValues(_type);

        return ((_amount * _amountToUSD * tokenDecimal * 100) /
            (_typeDecimal * (10**8) * uint256(_price)));
    }

    // Returns the crypto values used
    function cryptoValues(uint8 _type)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 _amountToUSD;
        uint256 _typeDecimal;

        if (_type == 1) {
            _amountToUSD = OracleWrapper(BNBorETHOracleAddress).latestAnswer();
            _typeDecimal = 10**18;
        } else {
            _amountToUSD = OracleWrapper(USDTOracleAddress).latestAnswer();
            _typeDecimal = uint256(10**Token(USDTAddress).decimals());
        }

        // For unit tests
        // if (_type == 1) {
        //     _amountToUSD = 1000000 * (10**8);
        //     _typeDecimal = 10**18;
        // } else {
        //     _amountToUSD = 100000 * (10**8);
        //     _typeDecimal = uint256(10**Token(USDTAddress).decimals());
        }

        return (_amountToUSD, _typeDecimal);
    }

    // Sets phase info according to the tokens bought
    function setPhaseInfo(uint256 _tokensUserWillGet, uint8 _phaseNo) internal {
        require(_phaseNo <= 5, "All tokens has been exhausted");

        Phases storage pInfo = phaseInfo[_phaseNo];

        if (block.timestamp < pInfo.expirationTimestamp) {
            //  when phase has more tokens than reuired
            if ((pInfo.tokenLimit - pInfo.tokenSold) > _tokensUserWillGet) {
                pInfo.tokenSold += _tokensUserWillGet;
            }
            //  when  phase has equal tokens as reuired
            else if (
                (pInfo.tokenLimit - pInfo.tokenSold) == _tokensUserWillGet
            ) {
                pInfo.tokenSold = pInfo.tokenLimit;
                pInfo.isComplete = true;
            }
            // when tokens required are more than left tokens in phase
            else {
                uint256 tokensLeft = _tokensUserWillGet -
                    (pInfo.tokenLimit - pInfo.tokenSold);
                pInfo.tokenSold = pInfo.tokenLimit;
                pInfo.isComplete = true;

                setPhaseInfo(tokensLeft, _phaseNo + 1);
            }
        }
        // if tokens left in phase afterb completion of expiration time
        else {
            uint256 remainingTokens = pInfo.tokenLimit - pInfo.tokenSold;
            pInfo.tokenSold = pInfo.tokenLimit;
            pInfo.isComplete = true;

            phaseInfo[_phaseNo + 1].tokenLimit += remainingTokens;
            setPhaseInfo(_tokensUserWillGet, _phaseNo + 1);
        }
    }

    // Function sends the left over tokens to the receiving address, only after phases are over
    function sendLeftoverTokens() external onlyOwner {
        require(
            block.timestamp > phaseInfo[5].expirationTimestamp,
            "Phases are not over yet"
        );

        uint256 _balance = Token(tokenAddress).balanceOf(address(this));
        require(_balance > 0, "No tokens left to send");

        TransferHelper.safeTransfer(tokenAddress, receiverAddress, _balance);
    }

    // Returns the expected phase according to the timestamp. 0 if all phases are over
    function showCurrentPhase(uint8 _phaseNo) public view returns (uint8) {
        Phases memory pInfo = phaseInfo[_phaseNo];

        if (pInfo.expirationTimestamp > block.timestamp) {
            return _phaseNo;
        } else {
            return showCurrentPhase(_phaseNo + 1);
        }
    }

    /* ================ OTHER FUNCTIONS SECTION ================ */
    // Updates USDT Address
    function updateUSDTAddress(address _USDTAddress) external onlyOwner {
        USDTAddress = _USDTAddress;
    }

    // Updates USDT Oracle Address
    function updateUSDTOracleAddress(address _USDTOracleAddress)
        external
        onlyOwner
    {
        USDTOracleAddress = _USDTOracleAddress;
    }

    // Updates USDT Oracle Address
    function updateBNBorETHOracleAddress(address _BNBorETHOracleAddress)
        external
        onlyOwner
    {
        BNBorETHOracleAddress = _BNBorETHOracleAddress;
    }

    // Updates Receiver Address
    function updateReceiverAddress(address _receiverAddress)
        external
        onlyOwner
    {
        receiverAddress = _receiverAddress;
    }
}
