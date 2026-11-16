# Instructions ของ agent แต่ละตำแหน่งใน Paperclip

โฟลเดอร์นี้เป็นต้นฉบับของไฟล์ `AGENTS.md` ที่ส่งเข้า Paperclip ตอนสร้าง agent
(managed instructions bundle) หนึ่งไฟล์ต่อหนึ่งตำแหน่ง ผังรวมและเหตุผลอยู่ใน
[../paperclip-org-structure.md](../paperclip-org-structure.md)
ส่วนของ CEO อยู่ใน [../paperclip-ceo-role.md](../paperclip-ceo-role.md) หัวข้อ 8

| ไฟล์ | ชื่อ agent | role | รายงานต่อ |
| --- | --- | --- | --- |
| cto.md | CTO | cto | CEO |
| engineer-app.md | Engineer – App | engineer | CTO |
| engineer-web.md | Engineer – Web | engineer | CTO |
| reviewer-qa.md | Reviewer / QA | qa | CTO |
| release-coordinator.md | Release Coordinator | devops | CTO |
| cmo-growth.md | CMO / Growth | cmo | CEO |
| coo-field-ops.md | COO / Field Ops | pm | CEO |
| support-desk.md | Support Desk | general | COO / Field Ops |
| cfo-finance.md | CFO / Finance | cfo | CEO |
| security-data.md | Security & Data | security | CEO |
| researcher.md | Researcher | researcher | CEO |

กติกา:

- แก้ที่นี่ก่อน แล้วค่อยส่งเข้า Paperclip (ผ่านหน้า Instructions หรือ API) เพื่อให้ git
  เป็นประวัติของข้อความที่ agent ใช้จริง
- ห้ามใส่ token คีย์ หรือข้อมูลส่วนตัวในไฟล์เหล่านี้ agent ทุกตัวอ่านได้
- ทุกไฟล์มี "กติการ่วม" ชุดเดียวกัน ถ้าแก้กติการ่วม ให้แก้ทุกไฟล์พร้อมกัน
