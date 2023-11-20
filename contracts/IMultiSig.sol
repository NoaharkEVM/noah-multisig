// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiSig {
	enum TransactionState {
		Active,
		Canceled,
		Succeeded,
		Executed,
		Expired
	}

	event SignerAdded(address signer, uint256 weight);
	event SignerRemoved(address signer, uint256 weight);
	event SignerReplaced(address signer, address newSigner, uint256 weight);
	event ThresholdUpdated(uint256 threshold);
	event PeriodUpdated(uint256 period);
	event TotalWeightChanged(uint256 totalWeight);
	event Approved(address account, uint256 transactionId, uint256 signerWeight, uint256 transactionWeight);
	event Unapproved(address account, uint256 transactionId, uint256 signerWeight, uint256 transactionWeight);
	event TransactionCreated(
		uint256 transactionId,
		uint256 expiration,
		address account,
		address[] targets,
		uint256[] values,
		string[] signatures,
		bytes[] calldatas
	);
	event TransactionExecuted(uint256 transactionId);
	event TransactionCanceled(uint256 transactionId);

	function nonces(address owner) external view returns (uint256);

	function transactionLength() external view returns (uint256);

	function period() external view returns (uint256);

	function threshold() external view returns (uint256);

	function totalWeight() external view returns (uint256);

	function signerDetails() external view returns (address[] memory signers, uint256[] memory weights);

	function transactionDetails(
		uint256 transactionId
	)
		external
		view
		returns (
			address creator,
			uint256 weight,
			uint256 expiration,
			bool executed,
			bool canceled,
			address[] memory targets,
			uint256[] memory values,
			bytes[] memory calldatas
		);

	function state(uint256 transactionId) external view returns (TransactionState);

	function hasApproved(uint256 transactionId, address account) external view returns (bool);

	function signersForApproved(uint256 transactionId) external view returns (address[] memory);

	function setThreshold(uint256 threshold) external;

	function setPeriod(uint256 period) external;

	function approve(uint256 transactionId) external returns (uint256);

	function approveBySig(
		uint256 transactionId,
		uint256 nonce,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256);

	function unapproveBySig(
		uint256 transactionId,
		uint256 nonce,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256);

	function unapprove(uint256 transactionId) external returns (uint256);

	function submitTransaction(
		address[] memory targets,
		uint256[] memory values,
		bytes[] memory calldatas
	) external returns (uint256);

	function execute(uint256 transactionId) external payable;

	function cancel(uint256 transactionId) external;
}
