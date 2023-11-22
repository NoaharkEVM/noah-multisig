// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./IMultiSig.sol";

contract MultiSig is Context, ERC165, EIP712, IMultiSig, IERC721Receiver, IERC1155Receiver {
	using SafeCast for uint256;
	using EnumerableMap for EnumerableMap.AddressToUintMap;
	using EnumerableSet for EnumerableSet.AddressSet;
	using Counters for Counters.Counter;

	bytes32 public constant APPROVE_TYPEHASH = keccak256("Approve(uint256 transactionId)");
	bytes32 public constant UNAPPROVE_TYPEHASH = keccak256("Unapprove(uint256 transactionId)");

	error OnlySigner();
	error OnlySelf();
	error OnlyCreator(address creator);
	error ZeroThreshold();
	error ZeroPeriod();
	error ZeroSigner();
	error ZeroWeight();
	error SignerAlreadyExists(address signer);
	error SignerNotExists(address signer);
	error TransactionNotExists();
	error InvalidNonce();
	error InvalidTotalWeight(uint256 totalWeight, uint256 threshold);
	error AlreadyApproved(address signer);
	error NotExistsApproved(address signer);
	error NotASigner(address signer);
	error InvalidTransaction(uint256 transactionId);
	error InvalidTransactionLength(uint256 targets, uint256 calldatas, uint256 values);
	error InvalidSignerLenght(uint256 signers, uint256 weights);
	error InvalidState(TransactionState state);

	struct Transaction {
		address creator;
		address[] targets;
		uint256[] values;
		bytes[] calldatas;
		bool executed;
		bool canceled;
		uint256 expiration;
		uint256 weight;
	}
	uint256 private _period;
	uint256 private _threshold;
	uint256 private _totalWeight;
	uint256 private _transactionNonce;
	uint256[] private _transactionIds;
	EnumerableMap.AddressToUintMap private _signer; // account => weight
	mapping(address => Counters.Counter) private _nonces;
	mapping(uint256 => Transaction) private _transactions;
	mapping(uint256 => EnumerableSet.AddressSet) private _approvals;

	modifier onlySelf() {
		if (_msgSender() != address(this)) {
			revert OnlySelf();
		}
		_;
	}

	modifier onlySigner(address signer) {
		if (!_signer.contains(signer)) {
			revert OnlySigner();
		}
		_;
	}

	constructor(
		address[] memory signers,
		uint256[] memory weights,
		uint256 __threshold,
		uint256 __period
	) EIP712("noah-msig", "1") {
		if (__threshold == 0) {
			revert ZeroThreshold();
		}
		if (__period == 0) {
			revert ZeroPeriod();
		}
		uint256 length = signers.length;
		if (length != weights.length || length == 0) {
			revert InvalidSignerLenght(length, weights.length);
		}

		for (uint256 i = 0; i < length; i++) {
			_addSigner(signers[i], weights[i]);
		}

		_threshold = __threshold;
		_validateThreshold();

		_period = __period;
	}

	receive() external payable {}

	function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC165) returns (bool) {
		return
			interfaceId == type(IMultiSig).interfaceId ||
			interfaceId == type(IERC1155Receiver).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	function period() external view override returns (uint256) {
		return _period;
	}

	function threshold() external view override returns (uint256) {
		return _threshold;
	}

	function totalWeight() external view override returns (uint256) {
		return _totalWeight;
	}

	function transactionLength() external view override returns (uint256) {
		return _transactionIds.length;
	}

	function getWeight(address account) external view returns (uint256) {
		return _getWeight(account);
	}

	function nonces(address owner) external view override returns (uint256) {
		return _nonces[owner].current();
	}

	function signerDetails() external view override returns (address[] memory signers, uint256[] memory weights) {
		uint256 length = _signer.length();
		if (length == 0) {
			return (signers, weights);
		}
		signers = new address[](length);
		weights = new uint256[](length);
		for (uint256 i = 0; i < length; i++) {
			(signers[i], weights[i]) = _signer.at(i);
		}
	}

	function hasApproved(uint256 transactionId, address account) external view override returns (bool) {
		return _approvals[transactionId].contains(account);
	}

	function signersForApproved(uint256 transactionId) external view override returns (address[] memory) {
		return _approvals[transactionId].values();
	}

	function _getWeight(address account) private view returns (uint256) {
		(bool exists, uint256 weight) = _signer.tryGet(account);
		if (!exists) {
			revert NotASigner(account);
		}
		return weight;
	}

	function transactionDetails(
		uint256 transactionId
	)
		external
		view
		override
		returns (
			address creator,
			uint256 weight,
			uint256 expiration,
			bool executed,
			bool canceled,
			address[] memory targets,
			uint256[] memory values,
			bytes[] memory calldatas
		)
	{
		Transaction storage details = _transactions[transactionId];
		if (details.targets.length == 0) {
			revert TransactionNotExists();
		}
		return (
			details.creator,
			details.weight,
			details.expiration,
			details.executed,
			details.canceled,
			details.targets,
			details.values,
			details.calldatas
		);
	}

	function state(uint256 transactionId) external view override returns (TransactionState) {
		return _state(_transactions[transactionId]);
	}

	function _state(Transaction storage transaction) private view returns (TransactionState) {
		if (transaction.creator == address(0)) {
			revert TransactionNotExists();
		}
		if (transaction.executed) {
			return TransactionState.Executed;
		}

		if (transaction.canceled) {
			return TransactionState.Canceled;
		}

		if (transaction.expiration <= block.timestamp) {
			return TransactionState.Expired;
		}

		if (transaction.weight >= _threshold) {
			return TransactionState.Succeeded;
		} else {
			return TransactionState.Active;
		}
	}

	function submitTransaction(
		address[] memory targets,
		uint256[] memory values,
		bytes[] memory calldatas
	) external override returns (uint256) {
		if (targets.length != values.length || targets.length != calldatas.length || targets.length == 0) {
			revert InvalidTransactionLength(targets.length, calldatas.length, values.length);
		}
		uint256 transactionId = ++_transactionNonce;
		_transactionIds.push(transactionId);

		uint256 expiration = block.timestamp + _period;
		_transactions[transactionId] = Transaction(
			_msgSender(),
			targets,
			values,
			calldatas,
			false, // executed
			false, // canceled
			expiration, // expiration
			0 //weight
		);
		_approve(transactionId, msg.sender);

		emit TransactionCreated(
			transactionId,
			expiration,
			_msgSender(),
			targets,
			values,
			new string[](targets.length),
			calldatas
		);

		return transactionId;
	}

	function execute(uint256 transactionId) external payable override onlySigner(_msgSender()) {
		Transaction storage transaction = _transactions[transactionId];

		TransactionState status = _state(transaction);

		if (status != TransactionState.Succeeded) {
			revert InvalidState(status);
		}
		transaction.executed = true;

		emit TransactionExecuted(transactionId);

		_execute(transaction.targets, transaction.values, transaction.calldatas);
	}

	function _execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas) private {
		string memory errorMessage = "MultiSig: call reverted without message";
		for (uint256 i = 0; i < targets.length; ++i) {
			(bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
			Address.verifyCallResult(success, returndata, errorMessage);
		}
	}

	function cancel(uint256 transactionId) external override {
		Transaction storage transaction = _transactions[transactionId];

		TransactionState status = _state(transaction);

		if (status == TransactionState.Canceled || status == TransactionState.Executed) {
			revert InvalidState(status);
		}
		if (
			transaction.creator != _msgSender() &&
			(status == TransactionState.Active || status == TransactionState.Succeeded)
		) {
			revert OnlyCreator(transaction.creator);
		}

		_transactions[transactionId].canceled = true;

		emit TransactionCanceled(transactionId);
	}

	function setThreshold(uint256 __threshold) external override onlySelf {
		if (_threshold == 0) {
			revert ZeroThreshold();
		}
		_threshold = __threshold;

		_validateThreshold();
		emit ThresholdUpdated(_threshold);
	}

	function setPeriod(uint256 __period) external override onlySelf {
		if (__period == 0) {
			revert ZeroPeriod();
		}
		_period = __period;

		emit PeriodUpdated(__period);
	}

	function _addSigner(address signer, uint256 weight) private {
		if (weight == 0) {
			revert ZeroWeight();
		}
		if (signer == address(0)) {
			revert ZeroSigner();
		}
		if (_signer.contains(signer)) {
			revert SignerAlreadyExists(signer);
		}

		_signer.set(signer, weight);

		uint256 newTotalWeight = _totalWeight + weight;
		_totalWeight = newTotalWeight;

		_validateThreshold();

		emit TotalWeightChanged(newTotalWeight);
		emit SignerAdded(signer, weight);
	}

	function addSigner(address signer, uint256 weight) public onlySelf {
		_addSigner(signer, weight);
	}

	function removeSigner(address signer) external onlySelf {
		(bool exists, uint256 weight) = _signer.tryGet(signer);
		if (!exists) {
			revert SignerNotExists(signer);
		}
		_signer.remove(signer);

		uint256 newTotalWeight = _totalWeight - weight;
		_totalWeight = newTotalWeight;

		_validateThreshold();
		emit TotalWeightChanged(newTotalWeight);
		emit SignerRemoved(signer, weight);
	}

	function replaceSigner(address signer, address newSigner, uint256 weight) external onlySelf {
		(bool exists, uint256 oldWeight) = _signer.tryGet(signer);
		if (!exists) {
			revert SignerNotExists(signer);
		}
		if (weight == 0) {
			revert ZeroWeight();
		}
		if (newSigner == address(0)) {
			revert ZeroSigner();
		}
		if (_signer.contains(newSigner)) {
			revert SignerAlreadyExists(newSigner);
		}

		_signer.remove(signer);
		_signer.set(newSigner, weight);

		uint256 newTotalWeight = _totalWeight - oldWeight + weight;
		_totalWeight = newTotalWeight;

		_validateThreshold();
		emit TotalWeightChanged(newTotalWeight);
		emit SignerReplaced(signer, newSigner, weight);
	}

	function _validateThreshold() private view {
		uint256 __totalWeight = _totalWeight;
		uint256 __threshold = _threshold;
		if (__totalWeight < __threshold) {
			revert InvalidTotalWeight(__totalWeight, __threshold);
		}
	}

	function approve(uint256 transactionId) external override returns (uint256) {
		address signer = _msgSender();
		return _approve(transactionId, signer);
	}

	function unapprove(uint256 transactionId) external override returns (uint256) {
		address signer = _msgSender();
		return _unapprove(transactionId, signer);
	}

	function approveBySig(
		uint256 transactionId,
		uint256 nonce,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override returns (uint256) {
		address signer = ECDSA.recover(
			_hashTypedDataV4(keccak256(abi.encode(APPROVE_TYPEHASH, transactionId, nonce))),
			v,
			r,
			s
		);

		if (nonce != _useNonce(signer)) {
			revert InvalidNonce();
		}

		return _approve(transactionId, signer);
	}

	function unapproveBySig(
		uint256 transactionId,
		uint256 nonce,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override returns (uint256) {
		address signer = ECDSA.recover(
			_hashTypedDataV4(keccak256(abi.encode(UNAPPROVE_TYPEHASH, transactionId, nonce))),
			v,
			r,
			s
		);
		if (nonce != _useNonce(signer)) {
			revert InvalidNonce();
		}
		return _unapprove(transactionId, signer);
	}

	function _approve(uint256 transactionId, address signer) private onlySigner(signer) returns (uint256) {
		Transaction storage transaction = _transactions[transactionId];
		TransactionState status = _state(transaction);
		if (status != TransactionState.Active) {
			revert InvalidState(status);
		}

		if (_approvals[transactionId].contains(signer)) {
			revert AlreadyApproved(signer);
		}
		_approvals[transactionId].add(signer);

		uint256 weight = _getWeight(signer);
		uint256 newTransactionWeight = transaction.weight + weight;
		transaction.weight = newTransactionWeight;

		emit Approved(signer, transactionId, weight, newTransactionWeight);

		return weight;
	}

	function _unapprove(uint256 transactionId, address signer) private onlySigner(signer) returns (uint256) {
		Transaction storage transaction = _transactions[transactionId];
		TransactionState status = _state(transaction);
		if (status != TransactionState.Active) {
			revert InvalidState(status);
		}

		if (!_approvals[transactionId].contains(signer)) {
			revert NotExistsApproved(signer);
		}

		_approvals[transactionId].remove(signer);

		uint256 weight = _getWeight(signer);
		uint256 newTransactionWeight = transaction.weight - weight;
		transaction.weight = newTransactionWeight;

		emit Unapproved(signer, transactionId, weight, newTransactionWeight);

		return weight;
	}

	function _useNonce(address owner) private returns (uint256 current) {
		Counters.Counter storage nonce = _nonces[owner];
		current = nonce.current();
		nonce.increment();
	}

	function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	function onERC1155Received(
		address,
		address,
		uint256,
		uint256,
		bytes memory
	) external pure override returns (bytes4) {
		return this.onERC1155Received.selector;
	}

	function onERC1155BatchReceived(
		address,
		address,
		uint256[] memory,
		uint256[] memory,
		bytes memory
	) external pure override returns (bytes4) {
		return this.onERC1155BatchReceived.selector;
	}
}
