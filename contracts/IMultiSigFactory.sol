// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiSigFactory {
	function isMultiSig(address account) external view returns (bool);

	function multiSigs(uint256 i) external view returns (address);

	function length() external view returns (uint256);

	function deploy(
		address[] memory signers,
		uint256[] memory weights,
		uint256 threshold,
		uint256 period
	) external returns (address);
}
