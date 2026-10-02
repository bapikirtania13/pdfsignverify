const { execSync } = require('child_process');
const fs = require('fs');
let home = process.env.USERPROFILE || process.env.HOME;
function findFiles(dir, match) {
  let res = [];
  try {
    for (let f of fs.readdirSync(dir, {withFileTypes: true})) {
      let full = dir + '/' + f.name;
      if (f.isDirectory()) res = res.concat(findFiles(full, match));
      else if (match(full)) res.push(full);
    }
  } catch(e){}
  return res;
}
let jars = findFiles(home + '/.gradle/caches/modules-2/files-2.1', n => (n.includes('itext') || n.includes('slf4j') || n.includes('bouncy')) && n.endsWith('.jar') && !n.endsWith('-sources.jar') && !n.endsWith('-javadoc.jar'));
let cp = '.;' + jars.join(';');
execSync(`javac -cp "${cp}" CheckAadhaar.java`, {stdio: 'inherit'});
execSync(`java -cp "${cp}" CheckAadhaar`, {stdio: 'inherit'});
