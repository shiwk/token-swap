import "@openzeppelin/contracts/access/Ownable.sol";
import "./lock.sol";

pragma solidity 0.6.12;

contract MerkleTreeGenerator is Ownable {

	using SafeMath for uint256;

	LockMapping candyReceipt;

	uint256 constant pathMaximalLength = 7;
	uint256 constant public MerkleTreeMaximalLeafCount = 1 << pathMaximalLength;
	uint256 constant treeMaximalSize = MerkleTreeMaximalLeafCount * 2;
	uint256 public MerkleTreeCount = 0;
	uint256 public ReceiptCountInTree = 0;
	mapping (uint256 => MerkleTree) indexToMerkleTree;
	address public Lock;

	struct MerkleTree {
		bytes32 root;
		uint256 leaf_count;
		uint256 first_receipt_id;
		uint256 size;
	}

	constructor (LockMapping _lock) public{
		Lock = address(_lock);
		candyReceipt = _lock;
	}

	//fetch receipts
	function ReceiptsToLeaves(uint256 _start, uint256 _leafCount) internal view returns (bytes32[] memory){
		bytes32[] memory leaves = new bytes32[](_leafCount);

		for(uint256 i = _start; i< _start + _leafCount; i++) {
			(
				,
				,
				string memory targetAddress,
				uint256 amount,
				,
				,
				) = candyReceipt.receipts(i);


			bytes32 amountHash = sha256(abi.encode(amount));
			bytes32 targetAddressHash = sha256(abi.encode(targetAddress));
			bytes32 receiptIdHash = sha256(abi.encode(i));

			leaves[i - _start] = (sha256(abi.encode(amountHash, targetAddressHash, receiptIdHash)));
		}

		return leaves;
	}

	//create new receipt
	function GenerateMerkleTree() external onlyOwner {

		uint256 receiptCount = candyReceipt.receiptCount() - ReceiptCountInTree;

		require(receiptCount > 0);

		uint256 leafCount = receiptCount < MerkleTreeMaximalLeafCount ? receiptCount : MerkleTreeMaximalLeafCount;
		bytes32[] memory leafNodes = ReceiptsToLeaves(ReceiptCountInTree, leafCount);


		bytes32[treeMaximalSize] memory allNodes;
		uint256 nodeCount;

		(allNodes, nodeCount) = LeavesToTree(leafNodes);

		MerkleTree memory merkleTree = MerkleTree(allNodes[nodeCount - 1], leafCount, ReceiptCountInTree, nodeCount);

		indexToMerkleTree[MerkleTreeCount] = merkleTree;
		ReceiptCountInTree = ReceiptCountInTree + leafCount;
		MerkleTreeCount = MerkleTreeCount + 1;
	}

	//get users merkle tree path
	function GenerateMerklePath(uint256 _receiptId) public view returns(uint256, uint256, bytes32[pathMaximalLength] memory, bool[pathMaximalLength] memory) {

		require(_receiptId < ReceiptCountInTree);
		uint256 treeIndex = MerkleTreeCount - 1;
		for (; treeIndex >= 0 ; treeIndex--){

			if (_receiptId >= indexToMerkleTree[treeIndex].first_receipt_id)
			break;
		}

		bytes32[pathMaximalLength] memory neighbors;
		bool[pathMaximalLength] memory isLeftNeighbors;
		uint256 pathLength;

		MerkleTree memory merkleTree = indexToMerkleTree[treeIndex];
		uint256 index = _receiptId - merkleTree.first_receipt_id;
		(pathLength, neighbors, isLeftNeighbors) = GetPath(merkleTree, index);
		return (treeIndex, pathLength, neighbors, isLeftNeighbors);
	}

	function LeavesToTree(bytes32[] memory _leaves) internal pure returns (bytes32[treeMaximalSize] memory, uint256){
		uint256 leafCount = _leaves.length;
		bytes32 left;
		bytes32 right;

		uint256 newAdded = 0;
		uint256 i = 0;

		bytes32[treeMaximalSize] memory nodes;

		for (uint256 t = 0; t < leafCount ; t++)
		{
			nodes[t] = _leaves[t];
		}

		uint256 nodeCount = leafCount;
		if(_leaves.length % 2 == 1) {
			nodes[leafCount] = (_leaves[leafCount - 1]);
			nodeCount = nodeCount + 1;
		}


		// uint256 nodeToAdd = nodes.length / 2;
		uint256 nodeToAdd = nodeCount / 2;

		while( i < nodeCount - 1) {

			left = nodes[i++];
			right = nodes[i++];
			nodes[nodeCount++] = sha256(abi.encode(left,right));
			if (++newAdded != nodeToAdd)
			continue;

			if (nodeToAdd % 2 == 1 && nodeToAdd != 1)
			{
				nodeToAdd++;
				nodes[nodeCount] = nodes[nodeCount - 1];
				nodeCount++;
			}

			nodeToAdd /= 2;
			newAdded = 0;
		}

		return (nodes, nodeCount);
	}

	function GetPath(MerkleTree memory _merkleTree, uint256 _index) internal view returns(uint256, bytes32[pathMaximalLength] memory, bool[pathMaximalLength] memory){

		bytes32[] memory leaves = ReceiptsToLeaves(_merkleTree.first_receipt_id, _merkleTree.leaf_count);
		bytes32[treeMaximalSize] memory allNodes;
		uint256 nodeCount;

		(allNodes, nodeCount)= LeavesToTree(leaves);
		require(nodeCount == _merkleTree.size);

		bytes32[] memory nodes = new bytes32[](_merkleTree.size);
		for (uint256 t = 0; t < _merkleTree.size; t++){
			nodes[t] = allNodes[t];
		}

		return GeneratePath(nodes, _merkleTree.leaf_count, _index);
	}

	function GeneratePath(bytes32[] memory _nodes, uint256 _leafCount, uint256 _index) internal pure returns(uint256, bytes32[pathMaximalLength] memory,bool[pathMaximalLength] memory){
		bytes32[pathMaximalLength] memory neighbors;
		bool[pathMaximalLength] memory isLeftNeighbors;
		uint256 indexOfFirstNodeInRow = 0;
		uint256 nodeCountInRow = _leafCount;
		bytes32 neighbor;
		bool isLeftNeighbor;
		uint256 shift;
		uint256 i = 0;

		while (_index < _nodes.length - 1) {

			if (_index % 2 == 0)
			{
				// add right neighbor node
				neighbor = _nodes[_index + 1];
				isLeftNeighbor = false;
			}
			else
			{
				// add left neighbor node
				neighbor = _nodes[_index - 1];
				isLeftNeighbor = true;
			}

			neighbors[i] = neighbor;
			isLeftNeighbors[i++] = isLeftNeighbor;

			nodeCountInRow = nodeCountInRow % 2 == 0 ? nodeCountInRow : nodeCountInRow + 1;
			shift = (_index - indexOfFirstNodeInRow) / 2;
			indexOfFirstNodeInRow += nodeCountInRow;
			_index = indexOfFirstNodeInRow + shift;
			nodeCountInRow /= 2;

		}

		return (i, neighbors,isLeftNeighbors);
	}

	function GetMerkleTreeNodes(uint256 _treeIndex) public view returns (bytes32[] memory, uint256){
		MerkleTree memory merkleTree = indexToMerkleTree[_treeIndex];
		bytes32[] memory leaves = ReceiptsToLeaves(merkleTree.first_receipt_id, merkleTree.leaf_count);
		bytes32[treeMaximalSize] memory allNodes;
		uint256 nodeCount;

		(allNodes, nodeCount)= LeavesToTree(leaves);
		require(nodeCount == merkleTree.size);

		bytes32[] memory nodes = new bytes32[](merkleTree.size);
		for (uint256 t = 0; t < merkleTree.size; t++){
			nodes[t] = allNodes[t];
		}
		return (nodes, merkleTree.leaf_count);
	}

	function GetMerkleTree(uint256 _treeIndex) public view returns (bytes32, uint256, uint256, uint256){
		require(_treeIndex < MerkleTreeCount);
		MerkleTree memory merkleTree = indexToMerkleTree[_treeIndex];
		return (merkleTree.root, merkleTree.first_receipt_id, merkleTree.leaf_count, merkleTree.size);
	}
}