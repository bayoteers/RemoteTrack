# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

=head1 NAME

Bugzilla::Extension::RemoteTrack::Source::Bugzilla

=head1 DESCRIPTION

Interface for Bugzilla Source

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteTrack::Source::Bugzilla;

use base qw(Bugzilla::Extension::RemoteTrack::Source);

use Bugzilla::Error;
use Bugzilla::Util qw(datetime_from);

use Data::Dumper;
use XMLRPC::Lite;

sub check_options {
    my ($invocant, $options) = @_;
    for my $key (keys %$options) {
        my $value = $options->{$key};
        if ($key eq 'base_url') {
            my $uri = URI->new($value);
            ThrowUserError('invalid_parameter', {
                name => 'options->base_url',
                err => 'base_url has to be http(s)://...'}
            ) unless ($uri->scheme =~ /https?/);
            $value = $uri->scheme . ":" . $uri->opaque;
            $value .= "/" unless ($value =~ /\/$/);
        } elsif ($key eq 'from_email') {
            unless (!$value || ($value !~ /\P{ASCII}/
                && $value =~ /^${Email::Address::addr_spec}$/))
            {
                ThrowUserError('invalid_parameter', {
                    name => 'from email',
                    err => "'$value' is not a valid email address"
                });
            }
        } elsif ($key eq 'post_comments' || $key eq 'post_changes') {
            $value = $value ? 1 : 0
        } elsif ($key ne 'username' && $key ne 'password') {
            $value = undef;
        }
        if (defined $value) {
            $options->{$key} = $value;
        } else {
            delete $options->{$key};
        }
    }
    if (!defined $options->{base_url}) {
        ThrowUserError('invalid_parameter', {
            name => 'options->base_url',
            err => 'base_url is required' });
    }
    return $options;
}

sub handle_mail_notification {
    my ($self, $email) = @_;
    my $bz_url = $email->header('X-Bugzilla-URL') || '';
    my $from = $email->header('From') || '';
    my $action = $email->header('X-Bugzilla-Type') || '';
    return 0 if ($self->options->{base_url} ne $bz_url
                 || $self->options->{from_email} ne $from
                 || $action ne 'changed');

    my $msgid = $email->header('Message-ID');
    my ($id) = $msgid =~ /^<bug-(\d*)-/;
    if ($id) {
        my $urls = Bugzilla::Extension::RemoteTrack::Url->match({
            source_id => $self->id,
            value => $self->options->{base_url}."show_bug.cgi?id=$id",
        });
        for my $url (@$urls) {
            $url->remote2local;
        }
    } else {
        ThrowCodeError('remotetrack_email_error', {
            err => "Failed to parse bug ID from message ID '$msgid'",
        });
    }
    return 1;
}

sub is_valid_url {
    my ($self, $url) = @_;
    return 0 unless $self->SUPER::is_valid_url($url);
    my $base = $self->options->{base_url};
    return ($url =~ /^$base/) ? 1 : 0;
}

sub _bug_id_from_url {
    my ($self, $url) = @_;
    ThrowCodeError('invalid_parameter',
        {
            name => 'url',
            err => "URL '$url' is not a valid url for source ".$self->name,
        }
    ) unless $self->is_valid_url($url);
    my ($bug_id) = $url =~ /id=(\d+)/;
    return $bug_id;
}

sub fetch_comments {
    my ($self, $url, $since) = @_;
    my $bug_id = $self->_bug_id_from_url($url);
    my $params = {ids => [$bug_id]};
    if ($since) {
        $since = datetime_from($since);
        $since->set_time_zone('UTC');
        $params->{new_since} = $since->ymd('').'T'.$since->hms.'Z';
    }
    my $result = $self->_xmlrpc('Bug.comments', $params);
    my @comments;
    return \@comments unless defined $result;
    for my $c (@{$result->{bugs}->{$bug_id}->{comments}}) {
        push(@comments,
            {
                who => $c->{creator}, when => $c->{creation_time}.'Z',
                text => $c->{text},
                url => $self->_comment_url($bug_id, $c->{count})
            }
        );
    }
    return \@comments;
}

sub fetch_status_changes {
    my ($self, $url, $since) = @_;
    my $bug_id = $self->_bug_id_from_url($url);
    $since = $since ? datetime_from($since) : undef;
    my $params = {ids => [$bug_id]};
    my $result = $self->_xmlrpc('Bug.history', $params);
    my @changes;
    return \@changes unless defined $result;
    for my $c (@{$result->{bugs}->[0]->{history}}) {
        next if ($since && $since > datetime_from($c->{when}.'Z'));
        my ($status) = grep {$_->{field_name} eq 'status'} @{$c->{changes}};
        next unless ($status);
        my ($resolution)= grep {$_->{field_name} eq 'resolution'} @{$c->{changes}};
        my $from = $status->{removed};
        $from .= " / ".$resolution->{removed} if ($resolution && $resolution->{removed});
        my $to = $status->{added};
        $to .= " / ".$resolution->{added} if ($resolution && $resolution->{added});
        push(@changes,
            {
                who => $c->{who}, when => $c->{when}."Z",
                from => $from, to => $to
            }
        );
    }
    return \@changes;
}

sub _comment_url {
    my ($self, $bug_id, $cnum) = @_;
    return defined $cnum ?
        $self->options->{base_url}."show_bug.cgi?id=$bug_id#c$cnum" :
        '';
}

sub _can_post_comment {
    my $self = shift;
    return ($self->options->{username} && $self->options->{password}) ? 1 : 0;
}

sub _post_comment {
    my ($self, $url, $comment) = @_;
    return 0 unless $self->_can_post_comment;
    my $bug_id = $self->_bug_id_from_url($url);
    my $token = $self->_rpctoken;
    if (!$token) {
        return 0;
    }
    my $result = $self->_xmlrpc('Bug.add_comment',
        {
            id => $bug_id, comment => $comment, Bugzilla_token => $token,
        }
    );
    return $result ? 1 : 0;
}

sub post_changes {
    my ($self, $url, $changes) = @_;
    return 0 unless ($self->_can_post_comment && $self->options->{post_changes});

    my %vars;
    my @templates;
    if (defined $changes->{remotetrack_url}) {
        push(@templates, Bugzilla->params->{remotetrack_tracking_change_tmpl});
        $vars{tracking} = $changes->{remotetrack_url}->[0] eq $url ? 0 : 1;
    }
    if (defined $changes->{bug_status}) {
        push(@templates, Bugzilla->params->{remotetrack_status_change_tmpl});
        $vars{status} = $changes->{bug_status};
    }
    return 0 unless (@templates);

    my $message;
    my $message_template = join("\n", @templates);
    my $template = Bugzilla->template;
    $template->process(\$message_template, \%vars, \$message)
        || ThrowTemplateError($template->error());
    return $self->_post_comment($url, $message);
}

sub _rpctoken {
    my $self = shift;
    if (!defined $self->{_rpctoken}) {
        my $result = $self->_xmlrpc('User.login',
            {
                login => $self->options->{username},
                password => $self->options->{password},
            }
        );
        if ($result) {
            $self->{_rpctoken} = $result->{token};
        }
    }
    return $self->{_rpctoken};
}

sub _xmlrpc {
    my ($self, $method, $params) = @_;

    my $response = eval { $self->_rpcproxy->call($method, $params) };
    my $err = $@ ? $@ : $response->fault ? $response->faultstring : undef;
    if ($err) {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Purity = 1;
        warn "Remote Bugzilla XMLRPC call $method(".Dumper($params).") failed: ". $err;
        # TODO better error handling
        return undef;
    }
    return $response->result;
}

sub _rpcproxy {
    my $self = shift;
    if (!defined $self->{_rpcproxy}) {
        $self->{_rpcproxy} ||= XMLRPC::Lite->proxy($self->options->{base_url}."xmlrpc.cgi");
        my $proxy_url = Bugzilla->params->{'proxy_url'};
        if ($proxy_url) {
            $self->{_rpcproxy}->transport->proxy(['http', 'https'], $proxy_url);
        } else {
            $self->{_rpcproxy}->transport->env_proxy;
        }
    }
    return $self->{_rpcproxy};
}
1;
