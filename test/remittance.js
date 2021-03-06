const Remittance = artifacts.require('./Remittance.sol');
const isTxSuccessful = require('../utils/isTxSuccessful');
const Promise = require('bluebird');

if (typeof web3.eth.getBlockPromise !== "function") {
    Promise.promisifyAll(web3.eth, { suffix: "Promise" });
}

contract('Remittance', (accounts) => {
    let rem;

    beforeEach("deploy new Remittance", async () => {
        rem = await Remittance.new(1425854, {from: accounts[0]});
    });

    it('should set commission', async () => {
        var tx = await rem.setCommission(100000, {from: accounts[0], gas: 200000});
        assert(isTxSuccessful(tx, 200000), "Transaction failed.");

        var commission = await rem.commission.call();
        assert.equal(commission, 100000, "Commission not set.");
    });

    it('should have owner', async () => {
        var owner = await rem.getOwner.call({from: accounts[0]});
        assert.equal(owner, accounts[0], "Owner not set correctly.");
    });

    it('should be pausible only by owner', async () => {
        var isRunning = await rem.isRunning.call()
        assert.equal(isRunning, true, "isRunning 1 incorrect.");
        var tx = await rem.pause({from: accounts[0]});
        isRunning = await rem.isRunning.call()
        assert.equal(isRunning, false, "isRunning 2 incorrect.");
        try {
            tx = await rem.setCommission(100000, {from: accounts[0]});
            assert(false, "Revert expected");
        } catch(e) {
            tx = await rem.resume({from: accounts[0]});
            isRunning = await rem.isRunning.call()
            assert.equal(isRunning, true, "isRunning 3 incorrect.");
            tx = await rem.setCommission(100000, {from: accounts[0], gas: 200000});
            assert(isTxSuccessful(tx, 200000), "Transaction failed.");
        }
    });

    it('should add withdraw', async () => {
        var alice = accounts[1];
        var carol = accounts[2];
        var pass = 'pass';
        var passHash = await rem.createHash.call(pass);
        var deadline = Math.floor(Date.now() / 1000 + 120);
        var value = web3.toWei(1, "ether");

        var tx = await rem.addWithdraw(passHash, deadline, carol, {from: alice, value: value, gas: 200000});
        assert(isTxSuccessful(tx, 200000), "Transaction failed.");

        var w = await rem.withdraws.call(passHash);
        assert.equal(w[0].toNumber(), value, "Value is set incorrectly.");
        assert.equal(w[1].toNumber(), deadline, "Deadline is set incorrectly.");
        assert.equal(w[2], carol, "Beneficiary is set incorrectly.");
        assert.equal(w[3], alice, "Creator is set incorrectly.");
    });

    it('should allow beneficiary to withdraw ether', async () => {
        // set commission
        var tx = await rem.setCommission(100000, {from: accounts[0], gas: 200000});
        assert(isTxSuccessful(tx, 200000), "Transaction failed.");

        var commission = await rem.commission.call();
        assert.equal(commission, 100000, "Commission not set.");

        // add withdraw
        var alice = accounts[1];
        var carol = accounts[2];
        var pass = 'pass';
        var passHash = await rem.createHash.call(pass);
        var deadline = Math.floor(Date.now() / 1000 + 120);
        var value = web3.toWei(1, "ether");

        var tx = await rem.addWithdraw(passHash, deadline, carol, {from: alice, value: value, gas: 200000});
        assert(isTxSuccessful(tx, 200000), "addWithdraw transaction failed.");

        var w = await rem.withdraws.call(passHash);
        assert.equal(w[0].toNumber(), value, "Value is set incorrectly.");
        assert.equal(w[1].toNumber(), deadline, "Deadline is set incorrectly.");
        assert.equal(w[2], carol, "Beneficiary is set incorrectly.");
        assert.equal(w[3], alice, "Creator is set incorrectly.");
        
        var carolBal = await web3.eth.getBalancePromise(carol);
        
        // withdraw
        var tx = await rem.withdraw(pass, {from: carol, gasPrice: web3.toWei(1, "gwei"), gas: 200000});
        assert(isTxSuccessful(tx, 200000), "withdraw transaction failed.");
        
        var txCost = tx.receipt.gasUsed * web3.toWei(1, "gwei");
        var carolNewBal = await web3.eth.getBalancePromise(carol);
        
        assert.equal(
            carolNewBal.toNumber(),
            carolBal.plus(value).minus(txCost).minus(100000).toNumber(),
            "Carol balance does not match.");
    });

    // test comented because I couldn't find a way to revert evm_increaseTime
    // and it can interfere with other tests
    // it('should return value if withdraw passes deadline', async () => {
    //     // add withdraw
    //     var alice = accounts[1];
    //     var carol = accounts[2];
    //     var pass = 'pass';
        // var passHash = await rem.createHash.call(pass);
    //     var passHash = '0x' + abi.soliditySHA3(["bytes32"], [pass]).toString('hex');
    //     var deadline = Math.floor(Date.now() / 1000 + 100);
    //     var value = web3.toWei(1, "ether");

    //     var aliceBal = await web3.eth.getBalancePromise(alice);
    //     var tx = await rem.addWithdraw(passHash, deadline, carol, {from: alice, value: value, gasPrice: web3.toWei(1, "gwei"), gas: 200000});
    //.equal(isTxSuccessful(tx, 200000), "addWithdraw transaction failed.");
    //     var gasUsed = tx.receipt.gasUsed;

    //     var w = await rem.withdraws.call(passHash);
    //     assert.equal(w[0].toNumber(), value, "Value is set incorrectly.");
    //     assert.equal(w[1].toNumber(), deadline, "Deadline is set incorrectly.");
    //     assert.equal(w[2], carol, "Beneficiary is set incorrectly.");
    //     assert.equal(w[3], alice, "Creator is set incorrectly.");

    //     // move timer 200 sec, restart blockchain after that test!
    //     await web3.currentProvider.send({
    //         jsonrpc: "2.0", 
    //         method: "evm_increaseTime", 
    //         params: [200], id: 0
    //     });

    //     tx = await rem.cancelWithdraw(passHash, {from: alice, gasPrice: web3.toWei(1, "gwei")});
    //     gasUsed += tx.receipt.gasUsed;
    //     var txPrice = gasUsed * web3.toWei(1, "gwei");
    //     var aliceNewBal = await web3.eth.getBalancePromise(alice);

    //     assert.equal(
    //         aliceNewBal.toNumber(),
    //         aliceBal.minus(txPrice).toNumber(),
    //         "Alice balance is incorrect.");
    // });

});

