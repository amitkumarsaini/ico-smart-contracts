//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/ReentrancyGuard.sol";
import "./libraries/TransferHelper.sol";
import "./utils/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/OracleWrapper.sol";

contract CHBTeam is Ownable {
    address public tokenAddress; // CHB Token address
    uint64 public decimalValue; // Token decimals
    uint32 public startTimestamp; // Time at which contract is deployed
    uint32 public firstClaimTimestamp; // Time at which first first claim will be available
    uint32 public lastClaimTimestamp; // Time at which claims will be over
    uint32 public timeIntervals; // Time interval between 2 claims
    uint8 public totalTeams; // Total teams available
    uint8 public currentTeamCount;

    // Team Addresses
    address public DEVELOPMENT;
    address public MARKETING;
    address public SECURITY;
    address public LEGAL;

    /* ================ STRUCT SECTION ================ */
    // Struct for teams
    struct Team {
        address teamAddress;
        uint128 totalTokens;
        uint128 tokensClaimed;
        uint128 tokenDistribution;
        uint32 claimCount;
        uint32 vestingPeriod;
        bool isActive;
    }
    mapping(address => Team) public teamInfo;
    mapping(address => uint128) public teamShare;

    /* ================ EVENT SECTION ================ */
    event TeamCreated(
        address indexed teamAddress,
        uint128 totalTokens,
        uint128 tokensClaimed,
        uint128 tokenDistribution,
        uint32 claimCount,
        uint32 vestingPeriod
    );

    event TokensClaimed(
        address indexed teamAddress,
        uint128 tokensClaimed,
        uint32 claimCount
    );

    /* ================ CONSTRUCTOR SECTION ================ */
    // Construtor
    constructor(
        address _tokenAddress,
        address _development,
        address _marketing,
        address _security,
        address _legal
    ) {
        tokenAddress = _tokenAddress;
        DEVELOPMENT = _development;
        MARKETING = _marketing;
        SECURITY = _security;
        LEGAL = _legal;

        decimalValue = uint64(10**Token(tokenAddress).decimals());

        startTimestamp = uint32(block.timestamp);
        firstClaimTimestamp = startTimestamp + 5 minutes;
        lastClaimTimestamp = startTimestamp + 105 minutes;
        timeIntervals = 2 minutes;
        totalTeams = 4;

        teamShare[DEVELOPMENT] = 70_00_00_000 * decimalValue;
        teamShare[MARKETING] = 80_00_00_000 * decimalValue;
        teamShare[SECURITY] = 30_00_00_000 * decimalValue;
        teamShare[LEGAL] = 20_00_00_000 * decimalValue;

        registerTeam(DEVELOPMENT, teamShare[DEVELOPMENT]);
        registerTeam(MARKETING, teamShare[MARKETING]);
        registerTeam(SECURITY, teamShare[SECURITY]);
        registerTeam(LEGAL, teamShare[LEGAL]);
    }

    /* ================ TEAM FUNCTION SECTION ================ */

    // Function registers new team
    function registerTeam(address _teamAddress, uint128 _teamShare)
        public
        onlyOwner
    {
        // Only 4 teams are allowed
        require(currentTeamCount < 4, "Maximum teams created");

        // Team should not be already registered
        require(!teamInfo[_teamAddress].isActive, "Team already registered");

        // New team instance created
        Team memory newTeam = Team({
            teamAddress: _teamAddress,
            totalTokens: _teamShare,
            tokensClaimed: 0,
            tokenDistribution: (_teamShare * 200) / 10000,
            claimCount: 0,
            vestingPeriod: lastClaimTimestamp,
            isActive: true
        });
        teamInfo[_teamAddress] = newTeam;
        ++currentTeamCount;

        emit TeamCreated(
            _teamAddress,
            newTeam.totalTokens,
            newTeam.tokensClaimed,
            newTeam.tokenDistribution,
            newTeam.claimCount,
            newTeam.vestingPeriod
        );
    }

    // Function allows teams to claim tokens
    function claimTokens() public {
        Team storage tInfo = teamInfo[msg.sender];

        require(tInfo.isActive, "Team doesn't exist");
        require(block.timestamp > firstClaimTimestamp, "Tokens in vesting");

        uint32 _totalClaims = teamTotalClaims(firstClaimTimestamp, 0);
        if (_totalClaims > tInfo.claimCount) {
            uint128 _totalTokensToClaim = (_totalClaims - tInfo.claimCount) *
                tInfo.tokenDistribution;

            TransferHelper.safeTransfer(
                tokenAddress,
                msg.sender,
                _totalTokensToClaim
            );

            tInfo.claimCount = _totalClaims;
            tInfo.tokensClaimed += _totalTokensToClaim;
        } else {
            if (block.timestamp < firstClaimTimestamp) {
                require(false, "Vesting time is still on");
            } else {
                require(false, "Maximum tokens available already claimed");
            }
        }

        emit TokensClaimed(msg.sender, tInfo.tokensClaimed, tInfo.claimCount);
    }

    // Internal function to return claims
    function teamTotalClaims(uint32 _timestamp, uint32 _totalClaims)
        public
        view
        returns (uint32)
    {
        if (block.timestamp >= _timestamp) {
            if (_totalClaims < 50) {
                ++_totalClaims;
                return
                    teamTotalClaims(_timestamp + timeIntervals, _totalClaims);
            } else {
                return _totalClaims;
            }
        } else {
            return _totalClaims;
        }
    }
}
