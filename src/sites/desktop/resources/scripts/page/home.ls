require '../common/ui.js'
$ = require 'jquery'
TIMELINE_CORE = require '../common/timeline-core.js'

function post
	$form = $ \#post-form
	$submit-button = $form.find '[type=submit]'

	$submit-button.attr \disabled yes
	$submit-button.attr \value 'Updating...'

	$.ajax config.web-api-url + '/posts/status' {
		type: \post
		-process-data
		-content-type
		data: new FormData $form.0
		data-type: \json
		xhr-fields: {+with-credentials}}
	.done (data) ->
		$form[0].reset!
		$form.find \textarea .focus!
		$form.find \.image-attacher .find 'p, img' .remove!
		$form.find \.image-attacher .append $ '<p><i class="fa fa-picture-o"></i></p>'
		$submit-button.attr \disabled no
		$submit-button.attr \value 'Update \uf1d8'
		$.remove-cookie \post-autosave {path: '/'}
		window.display-message '投稿しました！'
	.fail (data) ->
		#$form[0].reset!
		$form.find \textarea .focus!
		$submit-button.attr \disabled no
		$submit-button.attr \value 'Update \uf1d8'
		error-code = JSON.parse data.response-text .error.code
		switch error-code
		| \empty-text => window.display-message 'テキストを入力してください。'
		| \too-long-text => window.display-message 'テキストが長過ぎます。'
		| \duplicate-content => window.display-message '投稿が重複しています。'
		| \failed-attach-image => window.display-message '画像の添付に失敗しました。Misskeyが対応していない形式か、ファイルが壊れているかもしれません。'
		| \denied-gif-upload => window.display-message 'GIFを投稿可能なのはplus-accountのみです。'
		| _ => window.display-message "不明なエラー (#error-code)"

$ ->
	try
		Notification.request-permission!
	catch
		console.log 'oops'

	TIMELINE_CORE.init $ '.timeline'

	/*
	# オートセーブがあるなら復元
	if $.cookie \post-autosave
		$ '#post-form textarea' .val $.cookie \post-autosave
	*/

	# 通知読み込み
	$.ajax config.web-api-url + '/notice/timeline-webhtml' {
		type: \get
		data: {}
		data-type: \json
		xhr-fields: {+with-credentials}}
	.done (data) ->
		if data != ''
			$notices = $ data
			$notices.each ->
				$notice = $ @
				$notice.append-to $ '#widget-notices .notices'
		else
			$info = $ '<p class="notice-empty">通知はありません</p>'
			$info.append-to $ '#widget-notices'
	.fail (data) ->

	socket = io.connect config.web-streaming-url + '/streaming/home'

	socket.on \connect ->
		console.log 'Connected'

	socket.on \disconnect (client) ->

	socket.on \notice (notice) ->
		console.log \notice notice

		$ '#widget-notices .notice-empty' .remove!

		$notice = ($ notice).hide!
		$notice.prepend-to ($ '#widget-notices .notices') .show 200

	socket.on \post (post) ->
		TIMELINE_CORE.add $ post

	socket.on \reply (status) ->
		console.log \reply status

		id = status.id
		name = status.user-name
		sn = status.user-screen-name
		text = status.text
		n = new Notification name, {
			body: text
			icon: status.user-icon-image-url
		}
		n.onshow = ->
			set-timeout ->
				n.close!
			, 10000ms
		n.onclick = ->
			window.open "#{conf.url}/#{sn}/status/#{id}"

	socket.on \talk-message (message) ->
		console.log \talk-message message
		window-id = 'misskey-window-talk-' + message.user.id
		if $('#' + window-id).0
			return
		n = new Notification message.user.name, {
			body: message.text,
			icon: message.user.icon-image-url
		}
		n.onshow = ->
			set-timeout ->
				n.close!
			, 10000ms
		n.onclick = ->
			url = config.url + '/widget/talk/' + message.user.screen-name
			$content = $ '<iframe>' .attr {
				src: url
				+seamless
			}
			open-window do
				window-id
				$content
				'<i class="fa fa-comments"></i>' + escapeHTML message.user.name
				300
				450
				true
				url

	# Read more
	$ window .scroll ->
		me = $ @
		current = $ window .scroll-top! + window.inner-height
		if current > $ document .height! - 32
			if not me.data \loading
				me.data \loading yes
				$.ajax "#{config.web-api-url}/web/desktop/home/posts/timeline" {
					type: \get
					data:
						limit: 20
						'max-cursor': $ '#widget-timeline .timeline > .posts > .post:last-child' .attr \data-timeline-cursor
					data-type: \text
					xhr-fields: {+with-credentials}}
				.done (data) ->
					me.data \loading no
					$posts = $ data
					$posts.each ->
						TIMELINE_CORE.add-last $ @
				.fail (data) ->
					me.data \loading no

	$ '#recommendation-users > .users > .user' .each ->
		$user = $ @
		$user.find \.follow-button .click ->
			$button = $ @
			$button.attr \disabled yes

			if ($user.attr \data-is-following) == \true
				$.ajax config.web-api-url + '/users/unfollow' {
					type: \delete
					data: { 'user-id': $user.attr \data-user-id }
					data-type: \json
					xhr-fields: {+with-credentials}
				} .done ->
					$button.attr \disabled no
					$button.remove-class \following
					$button.add-class \notFollowing
					$button.text 'フォロー'
					$user.attr \data-is-following \false
				.fail ->
					$button.attr \disabled no
			else
				$.ajax config.web-api-url + '/users/follow' {
					type: \post
					data: { 'user-id': $user.attr \data-user-id }
					data-type: \json
					xhr-fields: {+with-credentials}
				} .done ->
					$button.attr \disabled no
					$button.remove-class \notFollowing
					$button.add-class \following
					$button.text 'フォロー解除'
					$user.attr \data-is-following \true
				.fail ->
					$button.attr \disabled no
