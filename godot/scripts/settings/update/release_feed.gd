class_name ReleaseFeed

const RELEASES_PAGE := "https://github.com/%s/releases"
const REPO := "whitehml/deck-station"
const RELEASE_API := "https://api.github.com/repos/%s/releases/tags/latest"
const REQUEST_TIMEOUT := 20.0


static func failure_reason(code: int) -> String:
	var detail := ""
	match code:
		HTTPRequest.RESULT_CANT_RESOLVE:
			detail = "The address couldn't be resolved. Check DNS."
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			detail = "The connection failed. Check that you're on a network with internet access."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			detail = (
				"The TLS connection to GitHub failed. Check the system clock, or "
				+ "download the release by hand from\n%s" % [RELEASES_PAGE % REPO]
			)
		HTTPRequest.RESULT_TIMEOUT:
			detail = "The request timed out after %d seconds." % int(REQUEST_TIMEOUT)
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			detail = "Too many redirects."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			detail = "The download couldn't be written to disk."
		_:
			detail = "Check that you're on a network with internet access."
	return "%s\n\n(HTTPRequest result %d)" % [detail, code]
