// Compatibility variants of the canonical designer-provided SVG.
const fs=require('fs');
const source=fs.readFileSync('assets/brand/pokpok-icon.svg','utf8');
const mark=source.replace(/<rect width="1024"[^>]+\/>/,'').replace(/<rect x="80"[^>]+\/>/,'').replace(/^[ \t]+$/gm,'');
fs.writeFileSync('assets/brand/01-mark-burgundy.svg',mark);
// A monochrome reverse mark for dark backgrounds, using the same geometry.
const cream=mark.replace(/fill="url\(#(?:burgundy|pan)\)"/g,'fill="#F5F1EC"').replace(/fill="#760A24"/g,'fill="#F5F1EC"').replace(/<path d="M238 512 H786\s*C754[^>]+\/>/,'').replace('fill="#FFFFFF"','fill="#7A1F2B"');
fs.writeFileSync('assets/brand/02-mark-cream.svg',cream.replace(/^[ \t]+$/gm,''));
for(const name of ['03-app-icon.svg','03-app-icon-square.svg'])fs.writeFileSync('assets/brand/'+name,source);
for(const [name,colour,bg] of [['04-horizontal-burgundy.svg','#7A1F2B',''],['06-horizontal-reversed.svg','#F5F1EC','<rect width="1600" height="480" fill="#7A1F2B"/>']]){
 const nested=source.replace(/<\?xml[^>]+>\s*/,'').replace('width="1024" height="1024"','x="40" y="40" width="400" height="400"');
 fs.writeFileSync('assets/brand/'+name,`<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="480" viewBox="0 0 1600 480">${bg}${nested}<text x="500" y="260" font-family="IBM Plex Sans Thai, sans-serif" font-size="170" font-weight="300" fill="${colour}">pokpok</text><text x="510" y="350" font-family="sans-serif" font-size="36" letter-spacing="8" fill="${colour}">POINT OF SALE</text></svg>\n`);
}
