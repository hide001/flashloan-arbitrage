pragma solidity ^0.5.0;

interface ILendingPool {
    function flashLoan ( address _receiver, address _reserve, uint256 _amount, bytes calldata _params ) external;
    function getReserveData(address _reserve)
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 availableLiquidity,
            uint256 totalBorrowsStable,
            uint256 totalBorrowsVariable,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 utilizationRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            address mTokenAddress,
            uint40 lastUpdateTimestamp
        );
}