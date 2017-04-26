# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteTrack::Pages;
use warnings;
use strict;

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util qw(correct_urlbase);

use Bugzilla::Extension::RemoteTrack::Source;
use Bugzilla::Extension::RemoteTrack::Url;

sub source_html {
    my $vars = shift;

    ThrowUserError('auth_failure', {
            group => 'admin',
            action => 'access'
        }) unless Bugzilla->user->in_group('admin');

    my $input = Bugzilla->input_params;
    my $source_id = delete $input->{source_id};
    my $action = delete $input->{action} || '';
    my $source;
    if ($source_id) {
        $source = Bugzilla::Extension::RemoteTrack::Source->check({id=>$source_id});
    }
    if ($action eq 'save') {
        my $params = {
            name => delete $input->{name},
        };
        my %options;
        for my $key (keys %$input) {
            ($key) = $key =~ /option_(.*)/;
            next unless $key;
            $options{$key} = delete $input->{"option_$key"};
        }
        $params->{options} = \%options;

        if ($source) {
            $source->set_all($params);
            $source->update();
            $vars->{message} = "rt_source_updated";
        } else {
            $params->{class} = delete $input->{class};
            $source = Bugzilla::Extension::RemoteTrack::Source->create($params);
            $vars->{message} = "rt_source_created";
        }
    } elsif ($action eq 'delete' && defined $source) {
        my $urls = Bugzilla::Extension::RemoteTrack::Url->match({
                active => 1,
                source_id => $source->id,
            });
        if (!@$urls) {
            $source->remove_from_db();
            $source = undef;
            $vars->{message} = "rt_source_deleted";
        } else {
            $vars->{message} = "rt_cant_delete_has_active_urls";
        }
    }
    $vars->{source} = $source;
    $vars->{action} = $action;
    $vars->{source_classes} = Bugzilla::Extension::RemoteTrack::Source->CLASSES;
    $vars->{sources} = [Bugzilla::Extension::RemoteTrack::Source->get_all()];
}


sub manual_sync_html {
    my $vars = shift;

    if(!Bugzilla->params->{remotetrack_manual_sync}) {
        $vars->{error} = "manual sync not allowed";
        return;
    }
    my $group = Bugzilla->params->{remotetrack_group};
    ThrowUserError('auth_failure', {
            group => $group,
            action => 'use',
            object => 'remotetrack_manual_sync'
        }) unless Bugzilla->user->in_group($group);

    my $input = Bugzilla->input_params;
    my $bug_id = $input->{bug_id};
    my $bug = Bugzilla::Bug->new($bug_id);
    $vars->{bug} = $bug;
    if ($bug->remotetrack_url_obj) {
        my $old_user = Bugzilla->user;
        Bugzilla->set_user(Bugzilla::User->check(Bugzilla->params->{remotetrack_user}));
        eval {
            $bug->remotetrack_url_obj->sync_from_remote();
        };
        Bugzilla->set_user($old_user);
        if ($@) {
            $vars->{error} = $@;
        } else {
            my $url = correct_urlbase() . "show_bug.cgi?id=$bug_id";
            print Bugzilla->cgi->redirect('-location' =>  $url);
            exit;
        }
    }
}

1;
