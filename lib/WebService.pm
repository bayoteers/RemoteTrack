# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>


package Bugzilla::Extension::RemoteTrack::WebService;
use strict;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::RemoteTrack::Source;

use base qw(Bugzilla::WebService);

use constant PUBLIC_METHODS => qw(
    valid_urls
    tracking_bugs
);

sub valid_urls {
    my ($self, $params) = @_;

    my $urls = $params->{urls};
    ThrowCodeError('param_required',
            {param => 'urls', function => 'valid_urls'})
        unless defined $urls;
    my @valid_urls;
    my @sources = Bugzilla::Extension::RemoteTrack::Source->get_all();
    for my $url (@$urls) {
        for my $source (@sources) {
            if ($source->is_valid_url($url)) {
                push (@valid_urls, $url);
                last;
            }
        }
    }
    return \@valid_urls;
}

sub tracking_bugs {
    my ($self, $params) = @_;
    Bugzilla->login(LOGIN_REQUIRED);

    my $remotes = delete $params->{remotes};
    ThrowCodeError('param_required',
            {param => 'remotes', function => 'tracking_bugs'})
            unless defined $remotes;
    my $create = delete $params->{create} ? 1 : 0;

    if (ref($remotes) ne "ARRAY") {
        $remotes = [$remotes];
    }
    my @aliases;
    my @urls;
    my @errors;
    for my $orig (@$remotes) {
        my $alias;
        my $url;
        my $err;
        if ($orig =~ /https?:\/\//) {
            $url = $orig;
            eval {
                $alias = Bugzilla::Extension::RemoteTrack::Source->url_to_alias($orig);
            };
            if ($@ || !$alias) {
                $err = "Unrecognized URL $url";
            }
        } elsif ($orig =~ /^\w+#\w+$/) {
            $alias = $orig;
            eval {
                $url = Bugzilla::Extension::RemoteTrack::Source->alias_to_url($alias);
            };
            if ($@ || !$url) {
                $err = "Unrecognized alias $alias";
            }
        } else {
            # Fatal error if the input is not alias or url
            ThrowUserError('invalid_parameter', {
                name => 'remotes',
                err => "'$orig' is not URL or alias of form XYZ#NNN",
            });
        }
        push(@aliases, $alias);
        push(@urls, $url);
        push(@errors, $err);
    }
    my %response;
    for my $i (0..scalar $#$remotes) {
        my $orig = $remotes->[$i];
        if ($errors[$i]) {
            $response{errors} ||= {};
            $response{errors}->{$orig} = $errors[$i];
            $response{$orig} = [];
            next;
        }
        my $bug = Bugzilla::Bug->new($aliases[$i]);
        if ($bug->error) {
            if ($create) {
                $bug = Bugzilla::Extension::RemoteTrack::Source->create_tracking_bug(
                    $urls[$i]
                );
            } else {
                $bug = undef;
            }
        }
        # Bug id is put in array for backward compatibility.
        # Would not be necessary as we now have at max one tracking bug for
        # one remote bug.
        if ($bug && $bug->remotetrack_url eq $urls[$i]) {
            $response{$orig} = [$bug->bug_id];
        } else {
            $response{$orig} = [];
        }

    }
    return \%response;
}
1;
