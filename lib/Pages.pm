# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteSync::Pages;
use warnings;
use strict;

use Bugzilla;

use Bugzilla::Extension::RemoteSync::Source;

sub source_html {
	my $vars = shift;

	ThrowUserError('auth_failure', {
            group => 'admin',
            action => 'access'
        }) unless Bugzilla->user->in_group('admin');

	my $cgi = Bugzilla->cgi;
	my $source_id = $cgi->param('source_id');
	my $action = $cgi->param('action') || '';
	my $source;
	if ($source_id) {
		$source = Bugzilla::Extension::RemoteSync::Source->check({id=>$source_id});
	}
	if ($action eq 'save') {
		my $params = {
			name => $cgi->param('name'),
			type => $cgi->param('type'),
			from_email => $cgi->param('from_email'),
			base_url => $cgi->param('base_url'),
		};
		if ($source) {
			$source->set_all($params);
			$source->update();
		} else {
			$source = Bugzilla::Extension::RemoteSync::Source->create($params);
		}
	} elsif ($action eq 'delete' && defined $source) {
		$source->remove_from_db();
		$source = undef;
	} else {
		$vars->{source} = $source;
	}
	$vars->{action} = $action;
	$vars->{source_types} = [Bugzilla::Extension::RemoteSync::Source->TYPES];
	$vars->{sources} = [Bugzilla::Extension::RemoteSync::Source->get_all()];
}

1;
