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

// 4. The files for agents mention only what exists
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
