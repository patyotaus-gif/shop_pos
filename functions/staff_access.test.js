const {test}=require('node:test');
const assert=require('node:assert/strict');
const {hashPin,matchesPin,priceCart,publicSale,staffCap}=require('./staff_access');
test('salted PIN hashes, legacy PIN, and malformed hashes',()=>{
 const a=hashPin('123456'),b=hashPin('123456');
 assert.notEqual(a.pinHash,b.pinHash);assert.equal(matchesPin('123456',a),true);
 assert.equal(matchesPin('000000',a),false);assert.equal(matchesPin('abcd',a),false);
 assert.equal(matchesPin('1234',{pin:'1234'}),true);assert.equal(matchesPin('1234',{pinHash:'x',pinSalt:'x'}),false);
});
test('staff prices and modifier cost snapshots come from catalog only',()=>{
 const products=new Map([['rice',{name:'Rice',price:50,costPrice:20,modifierGroupIds:['extras']}]]);
 const groups=new Map([['extras',{name:'Extras',required:true,multiSelect:false,options:[{id:'egg',name:'Egg',priceAdjust:10,costAdjust:3}]}]]);
 const line={productId:'rice',quantity:2,optionIds:['egg'],price:1};
 const sale=priceCart([line],products,groups,new Date());
 assert.equal(sale[0].subtotal,120);assert.equal(sale[0].costPrice,20);assert.equal(sale[0].modifiers[0].costAdjust,3);
 assert.throws(()=>priceCart([{...line,optionIds:[]}],products,groups,new Date()));
 assert.throws(()=>priceCart([{...line,optionIds:['egg','egg']}],products,groups,new Date()));
 assert.throws(()=>priceCart([{...line,quantity:0}],products,groups,new Date()));
 const clean=publicSale({items:sale,createdAt:{toDate:()=>new Date()}});
 assert.equal('costPrice' in clean.items[0],false);assert.equal('costAdjust' in clean.items[0].modifiers[0],false);
});
test('staff cap includes owner and preserves legacy restaurant',()=>{
 assert.equal(staffCap({tier:'solo'}),0);assert.equal(staffCap({tier:'lite'}),0);assert.equal(staffCap({tier:'full'}),2);
 assert.ok(staffCap({tier:'restaurant'})>100);assert.ok(staffCap({shopType:'restaurant'})>100);
});
