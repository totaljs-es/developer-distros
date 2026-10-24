const Fs = require('fs');
const Os = require('os');
const { execFile } = require('child_process');

const DOMAIN_FILE = '/etc/totaljs-developer/domain';
const SERVICES = [
	{ id: 'code', unit: 'totaljs-code', name: 'Code', about: 'The editor in the browser' },
	{ id: 'flow', unit: 'totaljs-flow', name: 'Flow', about: 'Visual programming' },
	{ id: 'pgadmin', unit: 'totaljs-postgres', name: 'pgAdmin', about: 'The database, in the browser' }
];
const SYSTEM = ['docker', 'totaljs-proxy', 'totaljs-postgres', 'totaljs-dns'];
// folders of /www that are the services themselves, not projects
const RESERVED = ['proxy', 'code', 'flow', 'services', 'center'];

var cache = null;
var cached = 0;

function run(cmd, args) {
	return new Promise(resolve => execFile(cmd, args, { timeout: 2500 }, (err, out) => resolve(err ? '' : String(out).trim())));
}

function read(path, fallback) {
	try {
		return Fs.readFileSync(path, 'utf8').trim() || fallback;
	} catch (e) {
		return fallback;
	}
}

async function state(unit) {
	return (await run('systemctl', ['is-active', unit])) || 'unknown';
}

// the address of the default route is the one that other computers reach (the one of Docker's bridge is not)
async function address() {
	var m = (await run('ip', ['route', 'get', '1.1.1.1'])).match(/\bsrc\s+(\d+\.\d+\.\d+\.\d+)/);
	return m ? m[1] : (await run('hostname', ['-I'])).split(/\s+/)[0] || '127.0.0.1';
}

function projects() {
	var items = [];
	try {
		var names = Fs.readdirSync('/www', { withFileTypes: true });
		for (var item of names) {
			if (item.isDirectory() && !item.name.startsWith('.') && RESERVED.indexOf(item.name) === -1 && /^[a-z0-9][a-z0-9-]*$/.test(item.name))
				items.push(item.name);
		}
	} catch (e) {}
	return items.sort();
}

async function gather() {

	var domain = read(DOMAIN_FILE, 'totaljs.developer');
	var release = read('/etc/os-release', '').match(/^PRETTY_NAME="?([^"\n]+)"?/m);
	var cpus = Os.cpus();
	var disk = (await run('df', ['-h', '--output=used,size,pcent', '/'])).split('\n').pop().trim().split(/\s+/);

	var services = [];
	for (var item of SERVICES)
		services.push({ id: item.id, name: item.name, about: item.about, url: 'http://' + item.id + '.' + domain, state: await state(item.unit) });

	var system = [];
	for (var unit of SYSTEM)
		system.push({ name: unit.replace(/^totaljs-/, ''), state: await state(unit) });

	return {
		domain: domain,
		address: await address(),
		center: 'http://' + domain,
		services: services,
		system: system,
		projects: projects().map(name => ({ name: name, url: 'http://' + name + '.' + domain })),
		machine: {
			name: Os.hostname(),
			system: release ? release[1] : 'Linux',
			kernel: Os.release(),
			arch: Os.arch(),
			uptime: Math.floor(Os.uptime()),
			cpu: ((cpus[0] || {}).model || '').trim(),
			cores: cpus.length,
			memory: { used: Math.round((Os.totalmem() - Os.freemem()) / 1048576), total: Math.round(Os.totalmem() / 1048576) },
			disk: { used: disk[0] || '', size: disk[1] || '', percent: disk[2] || '' }
		},
		database: {
			host: 'postgres',
			port: 5432,
			user: 'totaljs',
			compose: '/www/services/postgres/docker-compose.yml',
			passwords: '/www/services/postgres/.env'
		}
	};
}

ROUTE('GET /api/status/', async $ => {
	// the page asks every few seconds: a second of cache keeps many open windows from running the commands again and again
	if (!cache || Date.now() - cached > 1500) {
		cache = await gather();
		cached = Date.now();
	}
	$.json(cache);
});

ROUTE('GET /health/', $ => $.json({ ok: true }));
ROUTE('GET /', $ => $.file(PATH.public('index.html')));
