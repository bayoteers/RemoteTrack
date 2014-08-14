# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>


package Bugzilla::Extension::RemoteTrack::WebService;
use strict;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::RemoteTrack::Source;

use base qw(Bugzilla::WebService);

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

1;
