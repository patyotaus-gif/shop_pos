'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {buildCashReport}=require('./cash_report');
const {summarizeMovements}=require('./money_ledger');

test('report separates discounts, returns, cashiers and delivery channels',async()=>{
  const f=fixture();
  f.docs.set('shops/shop/sales/a',{total:100,discount:50,staffName:'แคชเชียร์ A',staffId:'A1',salesChannel:'grab'});
  f.docs.set('shops/shop/sales/old',{items:[{productName:'คุกกี้',quantity:3},{productName:'บราวนี่',quantity:2}]});
  const rows=[{kind:'sale',saleId:'a',salesMinor:10000,amountMinor:10000,method:'cash'},
    {kind:'refund',saleId:'old',salesMinor:-2500,amountMinor:-2500,refundMinor:2500,method:'cash'},
    {kind:'debtPayment',amountMinor:5000,method:'cash'}];
  const report=await f.db.runTransaction(tx=>buildCashReport(tx,f.db.collection('shops').doc('shop'),rows));
  assert.equal(report.complete,true);
  assert.equal(report.salesBeforeDiscount,150);assert.equal(report.discountTotal,50);
  assert.equal(report.returnedSales,25);assert.equal(report.refundBillCount,1);
  assert.equal(report.returnedItems.reduce((n,i)=>n+i.quantity,0),5);
  assert.deepEqual(report.cashiers,[{name:'แคชเชียร์ A',id:'A1'}]);
  assert.deepEqual(report.byChannel,{grab:100});
  assert.equal(report.cancelledBills,null);
  const summary=summarizeMovements(rows,1000);
  assert.equal(summary.grossTotal,75);assert.equal(summary.cashDebtCollections,50);
  assert.equal(summary.cashRefunds,25);assert.equal(summary.expectedCash,1125);
});

test('missing historical source is marked incomplete instead of inventing totals',async()=>{
  const f=fixture();
  const report=await f.db.runTransaction(tx=>buildCashReport(tx,f.db.collection('shops').doc('shop'),[
    {kind:'sale',saleId:'missing',salesMinor:10000}]));
  assert.equal(report.complete,false);
});
