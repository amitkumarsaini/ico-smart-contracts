// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface OracleWrapper {
    function latestAnswer() external view returns (uint128);
}
