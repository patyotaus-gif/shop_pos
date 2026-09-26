const {spawnSync}=require('node:child_process');
for(const file of ['admin_plan_rules.test.cjs','staff_access.integration.cjs']) {
 const result=spawnSync(process.execPath,[require('node:path').join(__dirname,file)],{stdio:'inherit',env:process.env});
 if(result.status!==0)process.exit(result.status||1);
}
