'use strict';
const { Contract } = require('fabric-contract-api');

class EHRContract extends Contract {
    async initLedger(ctx) {
        console.log('EHR Ledger Initialized');
    }
    async createRecord(ctx, id, patientName, data) {
        const record = { id, patientName, data, timestamp: new Date().toISOString() };
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(record)));
        return JSON.stringify(record);
    }
    async getRecord(ctx, id) {
        const data = await ctx.stub.getState(id);
        if (!data || data.length === 0) throw new Error(`Record ${id} not found`);
        return data.toString();
    }
}
module.exports.contracts = [EHRContract];
