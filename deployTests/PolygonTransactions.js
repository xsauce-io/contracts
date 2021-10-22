// Generated by ReScript, PLEASE EDIT WITH CARE
'use strict';

var Curry = require("rescript/lib/js/curry.js");
var LetOps = require("../test/library/LetOps.js");
var DeployHelpers = require("./DeployHelpers.js");

var ethMarketCapOraclePriceFeedAddress = ethers.utils.getAddress("0x67935f65D1577ced9f4929D3679A157E95C1c02c");

var btcMarketCapOraclePriceFeedAddress = ethers.utils.getAddress("0x18E4058491C3F58bC2f747A9E64cA256Ed6B318d");

var ethUSDPriceFeedAddress = ethers.utils.getAddress("0xF9680D99D6C9589e2a93a78A04A279e509205945");

function launchPolygonMarkets(param, deploymentArgs) {
  var treasury = param.treasury;
  var paymentToken = param.paymentToken;
  var longShort = param.longShort;
  var staker = param.staker;
  return LetOps.AwaitThen.let_(Curry._1(deploymentArgs.getNamedAccounts, undefined), (function (namedAccounts) {
                return LetOps.AwaitThen.let_(ethers.getSigners(), (function (loadedAccounts) {
                              var admin = loadedAccounts[1];
                              console.log("deploying markets");
                              return DeployHelpers.deployFlipp3ningPolygon(longShort, staker, treasury, admin, paymentToken, ethMarketCapOraclePriceFeedAddress, btcMarketCapOraclePriceFeedAddress, deploymentArgs.deployments, namedAccounts);
                            }));
              }));
}

function launch3thMarket(param, deploymentArgs) {
  var treasury = param.treasury;
  var paymentToken = param.paymentToken;
  var longShort = param.longShort;
  var staker = param.staker;
  return LetOps.AwaitThen.let_(Curry._1(deploymentArgs.getNamedAccounts, undefined), (function (namedAccounts) {
                return LetOps.AwaitThen.let_(ethers.getSigners(), (function (loadedAccounts) {
                              var admin = loadedAccounts[1];
                              console.log("deploying markets");
                              return DeployHelpers.deploy3TH_Polygon(longShort, staker, treasury, admin, paymentToken, ethUSDPriceFeedAddress, deploymentArgs.deployments, namedAccounts);
                            }));
              }));
}

exports.ethMarketCapOraclePriceFeedAddress = ethMarketCapOraclePriceFeedAddress;
exports.btcMarketCapOraclePriceFeedAddress = btcMarketCapOraclePriceFeedAddress;
exports.ethUSDPriceFeedAddress = ethUSDPriceFeedAddress;
exports.launchPolygonMarkets = launchPolygonMarkets;
exports.launch3thMarket = launch3thMarket;
/* ethMarketCapOraclePriceFeedAddress Not a pure module */
