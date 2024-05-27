//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { DeployDsc } from "../../script/DeployDsc.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "lib/openzepplin-contracts/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { MockMoreDebtDSC } from "../mocks/MockMoreDebtDSC.sol";
import { MockFailedMintDSC } from "../mocks/MockFailedMintDSC.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DSCEngineTest is Test{
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 5 ether;
    uint256 public constant AMOUNT_TO_LIQUIDATE = 5 ether;
    int256 public constant NEW_ETH_USD_PRICE = 500e8;
    uint8 public constant DECIMALS = 8;


    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
    }

    /////////////////////////
    /// Constructor Test ////
    /////////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfLengthsAreNotSame() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////
    /// Price Test ////
    ///////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////////
    /// Deposit Collateral Tests ////
    /////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralFailsIfBalanceLessThanCollateral() public {
        uint256 amountCollateralDeposited = 15 ether;
        vm.prank(USER);
        vm.expectRevert();
        dsce.depositCollateral(weth, amountCollateralDeposited);
    }

    // Mint Dsc tests

    modifier mintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testMintDscRevertsIfHealthFactorIsBroken() public {
        uint256 expectedHealthFactor = 0;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
    }

    function testMintDscUpdatesUserInformation() public mintedDsc{
        assertEq(dsce.getAmountDscMinted(USER), AMOUNT_DSC_TO_MINT);
    }

    // function testBurnDsc() public mintedDsc {
    //     dsce.burnDsc(AMOUNT_DSC_TO_MINT);
    //     assertEq(dsce.getAmountDscMinted(USER), 0);
    // }

    function testRedeemCollateralForDsc() public mintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        (uint256 dscMinted, uint256 collateral) = dsce.getAccountInformation(USER);
        assertEq(dscMinted, 0);
        assertEq(collateral, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // Liquidation Tests

    function testLiquidate() public mintedDsc {
        // Change the eth/usd price feed such that user's health factor breaks
        // Current status: 1 weth = $2000 
        // Deposited collateral: 10 eth in weth or $20,000 weth
        // Minted Dsc : 5 eth of dsc or $10,000 dsc
        // If 1 weth becomes worth $500, deposited collateral becomes $5000
        // Health Factor becomes 0.5

        MockV3Aggregator newEthUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            NEW_ETH_USD_PRICE
        );
        ethUsdPriceFeed = address(newEthUsdPriceFeed);
        (uint256 userCollateral, uint256 userDsc) = dsce.getAccountInformation(USER);
        console.log(userCollateral, userDsc);
        console.log(dsce.getUserHealthFactor(USER));
    }
}
