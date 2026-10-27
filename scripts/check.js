'use strict';

// The checks that run on every change: the JSON files are valid, the catalog and the recipes agree on the ids,
// the shell scripts have no syntax errors and the files for agents mention only what exists.
// It needs Node.js and nothing else.

const Fs = require('fs');
const Path = require('path');
const { spawnSync } = require('child_process');

const ROOT = Path.join(__dirname, '..');
const problems = [];

function walk(directory, list = []) {
	for (const entry of Fs.readdirSync(directory, { withFileTypes: true })) {

		if (['.git', 'node_modules', 'build', '.build', 'dist'].includes(entry.name))
			continue;

		const path = Path.join(directory, entry.name);

		if (entry.isDirectory())
			walk(path, list);
		else
			list.push(path);
	}
	return list;
}

const files = walk(ROOT);
const relative = file => Path.relative(ROOT, file).split(Path.sep).join('/');

// A template has placeholders (__MEMORY__) where the builder writes a value: they are replaced by 0 before it is parsed
function json(file) {
	try {
		return JSON.parse(Fs.readFileSync(file, 'utf8').replace(/__[A-Z_]+__/g, '0'));
	} catch (err) {
		problems.push(relative(file) + ' is not valid JSON: ' + err.message);
	}
}

// 1. Every JSON file is valid
for (const file of files.filter(file => file.endsWith('.json')))
	json(file);

// 2. The catalog and the recipes agree
const recipes = Fs.readdirSync(Path.join(ROOT, 'tools/image-builder/images'), { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
const catalog = json(Path.join(ROOT, 'manifests/index.json'));
const listed = catalog ? catalog.images.map(image => image.id).sort() : [];

if (JSON.stringify(recipes) !== JSON.stringify(listed))
	problems.push('manifests/index.json lists [' + listed + '] and the recipes are [' + recipes + ']');

for (const id of recipes) {

	const image = json(Path.join(ROOT, 'tools/image-builder/images', id, 'image.json'));
	const template = json(Path.join(ROOT, 'tools/image-builder/images', id, 'manifest.template.json'));
	const manifest = Fs.existsSync(Path.join(ROOT, 'manifests', id, 'manifest.json')) ? json(Path.join(ROOT, 'manifests', id, 'manifest.json')) : (problems.push('manifests/' + id + '/manifest.json does not exist'), null);

	for (const [name, value] of [['image.json', image], ['manifest.template.json', template], ['manifest.json', manifest]]) {
		if (value && value.id !== id)
			problems.push(id + '/' + name + ' says id "' + value.id + '"');
	}

	if (image && image.disk_gb && image.runtime && image.runtime.disk && image.disk_gb !== image.runtime.disk)
		problems.push(id + '/image.json: disk_gb (' + image.disk_gb + ') and runtime.disk (' + image.runtime.disk + ') differ');

	for (const entry of catalog ? catalog.images.filter(image => image.id === id) : []) {
		if (!Fs.existsSync(Path.join(ROOT, 'manifests', entry.manifest)))
			problems.push('the catalog points to ' + entry.manifest + ', which does not exist');
	}
}

// 3. No shell script has a syntax error
for (const file of files.filter(file => file.endsWith('.sh') || /\/(apply-menu-icons|totaljs-appmenu|totaljs-pasystray|90-totaljs-wizard|preinst|postinst|prerm|postrm)$/.test(relative(file)))) {

	const first = Fs.readFileSync(file, 'utf8').split('\n')[0];

	if (!/^#!.*\b(ba)?sh\b/.test(first))
		continue;

	const result = spawnSync('bash', ['-n', file], { encoding: 'utf8' });

	if (result.status !== 0)
		problems.push(relative(file) + ': ' + result.stderr.trim());
}

// 4. The wallpapers are what their generator makes, and every one has its image at 4K
const python = spawnSync('python3', ['--version'], { encoding: 'utf8' });

if (python.status === 0) {

	const temp = Fs.mkdtempSync(Path.join(require('os').tmpdir(), 'wallpapers-'));
	// the generator writes the path of the mascot relative to the folder of the SVGs: use the same depth
	const folder = Path.join(temp, 'shared', 'wallpapers', 'svg');
	Fs.mkdirSync(folder, { recursive: true });
	Fs.mkdirSync(Path.join(temp, 'shared', 'branding'), { recursive: true });
	Fs.copyFileSync(Path.join(ROOT, 'shared/branding/mascot.png'), Path.join(temp, 'shared/branding/mascot.png'));
	Fs.mkdirSync(Path.join(temp, 'shared/branding/toto'));
	Fs.copyFileSync(Path.join(ROOT, 'shared/branding/toto/toto-coding.png'), Path.join(temp, 'shared/branding/toto/toto-coding.png'));

	const made = spawnSync('python3', [Path.join(ROOT, 'shared/wallpapers/generate.py'), folder], { encoding: 'utf8', env: { ...process.env, TOTO: Path.join(temp, 'shared/branding/toto/toto-coding.png'), MASCOT: Path.join(temp, 'shared/branding/mascot.png'), LOGO: Path.join(ROOT, 'shared/branding/logo-totaljs.svg') } });

	if (made.status !== 0)
		problems.push('shared/wallpapers/generate.py failed: ' + made.stderr.trim());
	else {
		for (const name of Fs.readdirSync(folder)) {
			const committed = Path.join(ROOT, 'shared/wallpapers/svg', name);
			if (!Fs.existsSync(committed) || Fs.readFileSync(committed, 'utf8') !== Fs.readFileSync(Path.join(folder, name), 'utf8'))
				problems.push('shared/wallpapers/svg/' + name + ' is not what generate.py makes: run shared/wallpapers/export.sh');
			if (!Fs.existsSync(Path.join(ROOT, 'shared/wallpapers/4k', name.replace(/\.svg$/, '.jpg'))))
				problems.push('shared/wallpapers/4k/' + name.replace(/\.svg$/, '.jpg') + ' does not exist: run shared/wallpapers/export.sh');
		}
	}

	Fs.rmSync(temp, { recursive: true, force: true });
}

// 5. The boot splash: its script uses images that exist, its brackets close, and its SVGs are what the generator makes
const splash = Path.join(ROOT, 'shared/plymouth/totaljs');

if (Fs.existsSync(splash)) {

	const script = Fs.readFileSync(Path.join(splash, 'totaljs.script'), 'utf8');
	const open = (text, a, b) => text.split(a).length - text.split(b).length;

	for (const [a, b] of [['{', '}'], ['(', ')'], ['[', ']']])
		if (open(script, a, b) !== 0)
			problems.push('shared/plymouth/totaljs/totaljs.script: ' + a + ' and ' + b + ' do not match');

	for (const match of script.matchAll(/Image\("([^"]+)"\)/g))
		if (!Fs.existsSync(Path.join(splash, match[1])))
			problems.push('shared/plymouth/totaljs/totaljs.script uses ' + match[1] + ', which does not exist: run shared/plymouth/export.sh');

	const theme = Fs.readFileSync(Path.join(splash, 'totaljs.plymouth'), 'utf8');
	if (!/ModuleName=script/.test(theme) || !/ScriptFile=.*totaljs\.script/.test(theme) || !/ImageDir=.*themes\/totaljs$/m.test(theme))
		problems.push('shared/plymouth/totaljs/totaljs.plymouth does not point to the script of the theme');

	if (python.status === 0) {
		const folder = Fs.mkdtempSync(Path.join(require('os').tmpdir(), 'splash-'));
		const made = spawnSync('python3', [Path.join(ROOT, 'shared/plymouth/generate.py'), folder], { encoding: 'utf8' });

		if (made.status !== 0)
			problems.push('shared/plymouth/generate.py failed: ' + made.stderr.trim());
		else {
			for (const name of Fs.readdirSync(folder)) {
				const committed = Path.join(ROOT, 'shared/plymouth/svg', name);
				if (!Fs.existsSync(committed) || Fs.readFileSync(committed, 'utf8') !== Fs.readFileSync(Path.join(folder, name), 'utf8'))
					problems.push('shared/plymouth/svg/' + name + ' is not what generate.py makes: run shared/plymouth/export.sh');
				if (!Fs.existsSync(Path.join(splash, name.replace(/\.svg$/, '.png'))))
					problems.push('shared/plymouth/totaljs/' + name.replace(/\.svg$/, '.png') + ' does not exist: run shared/plymouth/export.sh');
			}
		}

		Fs.rmSync(folder, { recursive: true, force: true });
	}
}

// 6. The files for agents mention only what exists
const everything = new Set(files.map(relative));
const folders = new Set();

for (const path of everything) {
	const parts = path.split('/');
	for (let i = 1; i < parts.length; i++)
		folders.add(parts.slice(0, i).join('/'));
}

for (const doc of ['AGENTS.md', 'README.md', 'shared/README.md']) {

	const text = Fs.readFileSync(Path.join(ROOT, doc), 'utf8');

	for (const match of text.matchAll(/`([\w.\-/]+)`/g)) {

		const token = match[1].replace(/\/$/, '');

		// the generated folders and the paths that are examples or placeholders are not in git
		if (!token.includes('/') || /^(build|dist)\//.test(token) || /<|\*/.test(token) || token.startsWith('tools/image-builder/images/developer-ubuntu/assets') && token.split('/').length > 5)
			continue;

		if (!/\.(md|js|json|sh|yml)$/.test(token) && !/\/$/.test(match[1]))
			continue;

		if (!everything.has(token) && !folders.has(token))
			problems.push(doc + ' mentions ' + token + ', which does not exist');
	}
}

if (problems.length) {
	console.error(problems.map(problem => '- ' + problem).join('\n'));
	console.error('\n' + problems.length + ' problem(s)');
	process.exit(1);
}

console.log('OK: ' + files.filter(file => file.endsWith('.json')).length + ' JSON files, ' + recipes.length + ' recipes, ' + 'the shell scripts and the files for agents');
