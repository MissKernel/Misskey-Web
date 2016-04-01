//////////////////////////////////////////////////
// WEB SERVER
//////////////////////////////////////////////////

import * as cluster from 'cluster';
import * as fs from 'fs';
import * as http from 'http';
import * as https from 'https';
import * as path from 'path';
import * as express from 'express';
import * as expressSession from 'express-session';
import * as MongoStore from 'connect-mongo';
import * as compression from 'compression';
import * as bodyParser from 'body-parser';
import * as cookieParser from 'cookie-parser';
import * as csrf from 'csurf';
const acceptLanguage: any = require('accept-language');

const vhost: any = require('vhost');

import db from './db/db';
import { User } from './db/models/user';
import { UserSettings, IUserSettings, guestUserSettings } from './db/models/user-settings';
import name from './core/naming-worker-id';
import requestApi from './core/request-api';
import uatype from './detect-ua';

import config from './config';

import api from './api/server';
import resources from './resources-server';
import router from './router';

acceptLanguage.languages([
	'en',
	'ja'
]);

const worker = cluster.worker;

console.log(`Init ${name(worker.id)} server...`);

//////////////////////////////////////////////////
// SERVER OPTIONS

const store = MongoStore(expressSession);

const sessionExpires = 1000 * 60 * 60 * 24 * 365; // One Year
const subdomainOptions = {
	base: config.public.domain
};

const session: any = {
	name: config.sessionKey,
	secret: config.sessionSecret,
	resave: false,
	saveUninitialized: true,
	cookie: {
		path: '/',
		domain: `.${config.public.domain}`,
		httpOnly: true,
		secure: config.https.enable,
		expires: new Date(Date.now() + sessionExpires),
		maxAge: sessionExpires
	},
	store: new store({
		mongooseConnection: db
	})
};

//////////////////////////////////////////////////
// INIT SERVER PHASE

const app: express.Express = express();
app.disable('x-powered-by');
app.locals.compileDebug = false;
app.locals.cache = true;
// app.locals.pretty = '    ';
app.set('view engine', 'jade');

// Init API server
app.use(vhost(config.public.hosts.webApi, api(session)));

// Init static resources server
app.use(vhost(config.public.hosts.resources, resources()));

app.use(bodyParser.urlencoded({ extended: true }));
app.use(cookieParser(config.cookiePass));
app.use(compression());

app.use((req, res, next) => {
	// CORS
	res.header('Access-Control-Allow-Origin', config.public.url);
	res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
	res.header('Access-Control-Allow-Headers', 'Content-Type, csrf-token');
	res.header('Access-Control-Allow-Credentials', 'true');

	// intercept OPTIONS method
	if (req.method === 'OPTIONS') {
		res.sendStatus(200);
	} else {
		next();
	}

	// Security headers
	res.header('X-Frame-Options', 'SAMEORIGIN');
	res.header('X-XSS-Protection', '1; mode=block');
	res.header('X-Content-Type-Options', 'nosniff');

	// HSTS
	if (config.https.enable) {
		res.header(
			'Strict-Transport-Security',
			'max-age=10886400; includeSubDomains; preload');
	}

	// See http://web-tan.forum.impressrd.jp/e/2013/05/17/15269
	res.header('Vary', 'Accept-Language, User-Agent, Cookie');

	res.locals.isLogin =
		req.hasOwnProperty('session') &&
		req.session !== null &&
		req.session.hasOwnProperty('userId') &&
		(<any>req.session).userId !== null;

	const ua: string = uatype(req.headers['user-agent']);
	const noui: boolean = req.query.hasOwnProperty('noui');
	const cookieLang: boolean = req.cookies['ui-language'];
	const browserAcceptLanguageString: string = req.headers['accept-language'];

	const browserAcceptLanguage = browserAcceptLanguageString !== undefined && browserAcceptLanguageString !== null
		? acceptLanguage.get(browserAcceptLanguageString)
		: 'en';

	res.locals.config = config.public;
	res.locals.cookie = req.cookies;
	res.locals.pagePath = req.path;
	res.locals.noui = noui;
	res.locals.login = res.locals.isLogin;
	res.locals.ua = ua;
	res.locals.workerId = worker.id;

	if (res.locals.isLogin) {
		const userId: string = (<any>req).session.userId;
		requestApi('account/show', {}, userId).then((user: User) => {
			UserSettings.findOne({
				userId: userId
			}, (err: any, settings: IUserSettings) => {
				const lang = settings.uiLanguage !== null
					? settings.uiLanguage
					: browserAcceptLanguage;
				req.user = Object.assign({}, user, {_settings: settings.toObject()});
				res.locals.me = user;
				res.locals.userSettings = settings.toObject();
				res.locals.locale = require(`${__dirname}/locales/${lang}.json`);
				res.locals.lang = lang;
				next();
			});
		}, (err: any) => {
			res.status(500).send('API error');
		});
	} else {
		const lang = cookieLang !== undefined
			? cookieLang
			: browserAcceptLanguage;
		req.user = null;
		res.locals.me = null;
		res.locals.userSettings = guestUserSettings;
		res.locals.locale = require(`${__dirname}/locales/${lang}.json`);
		res.locals.lang = lang;
		next();
	}
});

// Session settings
app.use(expressSession(session));

// CSRF
app.use(csrf({
	cookie: false
}));
app.use((req, res, next) => {
	res.locals.csrftoken = req.csrfToken();
	next();
});

app.use(require('subdomain')(subdomainOptions));

// Statics
app.get('/favicon.ico', (req, res) => {
	res.sendFile(path.resolve(`${__dirname}/favicon.ico`));
});
app.get('/manifest.json', (req, res) => {
	res.sendFile(path.resolve(`${__dirname}/manifest.json`));
});

// Main routing
router(app);

//////////////////////////////////////////////////
// LISTEN PHASE

let server: http.Server | https.Server;
let port: number;

if (config.https.enable) {
	port = config.port.https;
	server = https.createServer({
		key: fs.readFileSync(config.https.keyPath),
		cert: fs.readFileSync(config.https.certPath)
	}, app);

	// 非TLSはリダイレクト
	http.createServer((req, res) => {
		res.writeHead(301, {
			Location: config.public.url + req.url
		});
		res.end();
	}).listen(config.port.http);
} else {
	port = config.port.http;
	server = http.createServer(app);
}

server.listen(port, () => {
	const listenhost: string = server.address().address;
	const listenport: number = server.address().port;

	console.log(
		`\u001b[1;32m${name(worker.id)} is now listening at ${listenhost}:${listenport}\u001b[0m`);
});
