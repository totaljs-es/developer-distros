'use strict';

// The page is built with textContent only: nothing that comes from the computer is ever read as HTML.
function el(tag, props, children) {
	var node = document.createElement(tag);
	for (var key in props || {})
		node[key] = props[key];
	for (var child of children || [])
		node.append(child);
	return node;
}

function state(value, label) {
	var cls = value === 'active' ? 'ok' : (value === 'unknown' ? '' : 'bad');
	return el('span', { className: 'state ' + cls }, [label || (value === 'active' ? 'Running' : (value === 'unknown' ? 'Unknown' : 'Stopped'))]);
}

function uptime(seconds) {
	var d = Math.floor(seconds / 86400);
	var h = Math.floor(seconds % 86400 / 3600);
	var m = Math.floor(seconds % 3600 / 60);
	return [d ? d + 'd' : '', h ? h + 'h' : '', m + 'm'].filter(Boolean).join(' ');
}

function render(d) {

	document.getElementById('domain').textContent = d.domain;
	document.getElementById('address').textContent = d.address;
	document.getElementById('where').textContent = d.machine.name + ' · ' + d.machine.system;

	var tiles = document.getElementById('services');
	tiles.replaceChildren();
	for (var s of d.services) {
		tiles.append(el('a', { className: 'tile' + (s.state === 'active' ? '' : ' down'), href: s.url, target: '_blank', rel: 'noopener' }, [
			el('strong', { textContent: s.name }),
			el('span', { textContent: s.about }),
			state(s.state),
			el('span', { className: 'url mono', textContent: s.url.replace(/^https?:\/\//, '') })
		]));
	}

	var projects = document.getElementById('projects');
	projects.replaceChildren();
	if (d.projects.length) {
		var list = el('div', { className: 'projects' });
		for (var p of d.projects)
			list.append(el('a', { href: p.url, target: '_blank', rel: 'noopener' }, [el('strong', { textContent: p.name }), el('br'), el('span', { className: 'mono note', textContent: p.url.replace('http://', '') })]));
		projects.append(list);
	} else {
		projects.append(el('p', { className: 'empty' }, [
			'Your projects will appear here. Create one in Code and it gets its own address: ',
			el('code', { textContent: 'my-project.' + d.domain }), '.'
		]));
	}

	var db = d.database;
	document.getElementById('connection').textContent = 'postgres://' + db.user + '@' + db.host + ':' + db.port + '/postgres';
	document.getElementById('passwords').textContent = db.passwords;
	document.getElementById('compose').textContent = db.compose;

	var m = d.machine;
	var rows = [
		['Kernel', m.kernel + ' (' + m.arch + ')'],
		['Uptime', uptime(m.uptime)],
		['CPU', m.cpu + ' (' + m.cores + ')'],
		['Memory', m.memory.used + ' / ' + m.memory.total + ' MiB'],
		['Disk', m.disk.used + ' / ' + m.disk.size + ' (' + m.disk.percent + ')']
	];
	var machine = document.getElementById('machine');
	machine.replaceChildren();
	for (var r of rows)
		machine.append(el('div', {}, [el('dt', { textContent: r[0] }), el('dd', { textContent: r[1] })]));

	var system = document.getElementById('system');
	system.replaceChildren();
	for (var u of d.system)
		system.append(state(u.state, u.name));
}

function pulse(ok) {
	var node = document.getElementById('pulse');
	node.className = 'pulse ' + (ok ? 'ok' : 'off');
	node.textContent = ok ? 'Updated ' + new Date().toLocaleTimeString() : 'Center does not answer';
}

async function tick() {
	try {
		var response = await fetch('/api/status/', { cache: 'no-store' });
		render(await response.json());
		pulse(true);
	} catch (e) {
		pulse(false);
	}
}

document.getElementById('copy').addEventListener('click', function() {
	var button = this;
	var done = function() {
		button.textContent = 'Copied';
		setTimeout(function() { button.textContent = 'Copy'; }, 1500);
	};
	if (navigator.clipboard)
		navigator.clipboard.writeText(document.getElementById('connection').textContent).then(done, function() {});
});

tick();
setInterval(tick, 5000);
