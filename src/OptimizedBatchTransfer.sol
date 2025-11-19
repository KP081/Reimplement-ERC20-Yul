// src/OptimizedBatchTransfer.sol
pragma solidity ^0.8.20;

contract OptimizedBatchTransfer {
    mapping(address => uint256) public balances;

    event Transfer(address indexed from, address indexed to, uint256 value);

    // Normal implementation for comparison
    function batchTransferNormal(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (bool) {
        require(recipients.length == amounts.length, "Length mismatch");

        uint256 totalAmount = 0;
        for (uint i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(balances[msg.sender] >= totalAmount, "Insufficient balance");

        balances[msg.sender] -= totalAmount;

        for (uint i = 0; i < recipients.length; i++) {
            balances[recipients[i]] += amounts[i];
            emit Transfer(msg.sender, recipients[i], amounts[i]);
        }

        return true;
    }

    // Yul optimized version
    function batchTransferYul(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (bool) {
        assembly {
            // Check length equality
            if iszero(eq(recipients.length, amounts.length)) {
                mstore(0x00, 0x08c379a0) // Error selector
                mstore(0x04, 0x20)
                mstore(0x24, 0x0f)
                mstore(0x44, "Length mismatch")
                revert(0x00, 0x64)
            }

            let len := recipients.length

            // Calculate total amount first
            let totalAmount := 0
            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 1)
            } {
                let amount := calldataload(add(amounts.offset, mul(i, 0x20)))
                totalAmount := add(totalAmount, amount)
            }

            // Calculate sender balance slot
            mstore(0x00, caller())
            mstore(0x20, 0x00) // balances mapping slot
            let senderSlot := keccak256(0x00, 0x40)
            let senderBalance := sload(senderSlot)

            // Check sufficient balance
            if lt(senderBalance, totalAmount) {
                mstore(0x00, 0x08c379a0)
                mstore(0x04, 0x20)
                mstore(0x24, 0x14)
                mstore(0x44, "Insufficient balance")
                revert(0x00, 0x64)
            }

            // Deduct total from sender
            senderBalance := sub(senderBalance, totalAmount)
            sstore(senderSlot, senderBalance)

            // Transfer to recipients
            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 1)
            } {
                let recipient := calldataload(
                    add(recipients.offset, mul(i, 0x20))
                )
                let amount := calldataload(add(amounts.offset, mul(i, 0x20)))

                // Calculate recipient balance slot
                mstore(0x00, recipient)
                mstore(0x20, 0x00)
                let recipientSlot := keccak256(0x00, 0x40)

                // Add to recipient
                let recipientBalance := sload(recipientSlot)
                recipientBalance := add(recipientBalance, amount)
                sstore(recipientSlot, recipientBalance)

                // Emit Transfer event
                // Transfer(address,address,uint256)
                mstore(0x00, amount)
                log3(
                    0x00,
                    0x20,
                    0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                    caller(),
                    recipient
                )
            }

            // Return true
            mstore(0x00, 0x01)
            return(0x00, 0x20)
        }
    }

    // Helper: Fund accounts for testing
    function mint(address account, uint256 amount) external {
        balances[account] += amount;
    }
}
