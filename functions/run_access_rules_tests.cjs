const {spawnSync}=require('node:child_process');
for(const file of ['admin_plan_rules.test.cjs','staff_access.integration.cjs','offline_sales.integration.cjs','accounting.integration.cjs','pickup.integration.cjs','customer_order.integration.cjs']) {
 const result=spawnSync(process.execPath,[require('node:path').join(__dirname,file)],{stdio:'inherit',env:process.env});
 if(result.status!==0)process.exit(result.status||1);
}
