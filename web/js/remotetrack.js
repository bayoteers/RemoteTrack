/**
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Pami Ketolainen <pami.ketolainen@jolla.com>
 */

(function( RemoteTrack, $, undefined ) {

    RemoteTrack.init = function(opts) {
        if(opts.userInGroup) {
            initEditor(opts);
        } else {
            markTracked(opts.url);
        }
    }


    function initEditor(opts) {
        var seeAlsoUrls = [];
        $("ul.bug_urls > li").each(function() {
            var item = $(this);
            var url = item.find("a").first().attr('href');
            seeAlsoUrls.push(url);
        })
        if(seeAlsoUrls.length == 0) return;

        new Rpc("RemoteTrack", "valid_urls", {urls: seeAlsoUrls})
            .done(function(result) {
                result.forEach(function(url) {
                    var link = $("ul.bug_urls a[href='" + url +"']");
                    if (link.size() == 0) return;
                    addRemoteTrackUrlSwitch(link.parent(), url, opts);
                })
                if(result.length > 0) {
                    var noTrackLi = $("<li>");
                    $("ul.bug_urls").append(noTrackLi);
                    addRemoteTrackUrlSwitch(noTrackLi, "", opts);
                }
            })
    }

    function addRemoteTrackUrlSwitch(item, url, opts) {
        var input = $("<input>")
            .attr("type", "radio")
            .attr("name", "remotetrack_url")
            .attr("value", url);
        if (url == opts.url) {
            input.attr("checked", "checked");
            if (url) {
                item.addClass('remotetrack-url');
            }
        }
        var label = $("<label>")
            .append(input)
            .append(url ? "Track" : "No tracking");
        item.append(label);

        if (opts.manualSyncEnabled && url && url == opts.url) {
            item.append(" ").append(
                $('<a>')
                .attr('href', "page.cgi?id=rt_manual_sync.html&amp;bug_id=" + opts.bugId )
                .text('Manual sync')
            );
        }
    }

    function markTracked(url) {
        if (!url) return;
        $("ul.bug_urls > li").each(function() {
            var item = $(this);
            if (item.find('a').first().attr('href') == url) {
                item.addClass('remotetrack-url').append(" Tracked");
                item.append(
                    $('<input>').attr('name', 'remotetrack_url')
                    .attr('type', 'hidden')
                    .attr('value', url)
                );
                return false;
            }
        });
    }

}( window.RemoteTrack = window.RemoteTrack || {}, jQuery ));
