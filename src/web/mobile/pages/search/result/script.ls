require '../../../common/scripts/ui.ls'
$ = require 'jquery'
Timeline = require '../../../common/scripts/timeline-core.ls'

$ ->
	timeline = new Timeline $ '#stream'

	$ '#stream > .read-more' .click ->
		$button = $ @
		$button.attr \disabled on
		$button.find \i .attr \class 'fa fa-spinner fa-spin'
		$button.find \p .text '読み込んでいます...'
		$.ajax "#{CONFIG.urls.api}/posts/search" {
			data:
				'query': QUERY
				'limit': 20
				'max-cursor': $ '#stream > .posts > .post:last-child' .attr \data-cursor
		} .done (posts) ->
			posts.for-each (post) ->
				timeline.add-last post
		.always ->
			$button.attr \disabled off
			$button.find \i .attr \class 'fa fa-sort-amount-desc'
			$button.find \p .text 'もっと読み込む'
