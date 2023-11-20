// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./MultiSig.sol";
import "./IMultiSigFactory.sol";

contract MultiSigFactory is IMultiSigFactory {
	event MultiSigCreated(address multiSig);
	address[] public override multiSigs;
	mapping(address => bool) public override isMultiSig;

	function length() external view override returns (uint256) {
		return multiSigs.length;
	}

	function deploy(
		address[] memory signers,
		uint256[] memory weights,
		uint256 threshold,
		uint256 period
	) external override returns (address) {
		address multiSig = address(new MultiSig(signers, weights, threshold, period));
		isMultiSig[multiSig] = true;
		multiSigs.push(multiSig);

		emit MultiSigCreated(multiSig);
		return multiSig;
	}
}
