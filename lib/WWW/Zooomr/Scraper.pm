package WWW::Zooomr::Scraper;
use strict;
use warnings;
use Carp;
use version; our $VERSION = qv('0.3.0');
use English qw( -no_match_vars );
use WWW::Mechanize;

use Path::Class qw( file );

my @fields;
my %defaults = (
   login_page  => 'http://www.zooomr.com/login/',
   upload_page => 'http://www.zooomr.com/photos/upload/?noflash=okiwill',
   logout_page => 'http://www.zooomr.com/logout/',
);

BEGIN {    # Generate simple accessors
   no warnings;
   no strict;
   @fields = qw(
     updater
     agent username password
     login_page upload_page logout_page
   );

   for my $param_name (@fields) {
      *{__PACKAGE__ . '::get_' . $param_name} = sub {
         return $_[0]->{$param_name};
      };
      *{__PACKAGE__ . '::set_' . $param_name} = sub {
         my $previous = $_[0]->{$param_name};
         $_[0]->{$param_name} = $_[1];
         return $previous;
      };
   } ## end for my $param_name (@fields)
} ## end BEGIN

sub new {
   my $package = shift;
   my $config = ref($_[0]) ? $_[0] : {@_};

   my $self = bless {%defaults}, $package;
   $self->reconfig($config);

   return $self;
} ## end sub new

sub reconfig {
   my $self = shift;
   my $config = ref($_[0]) ? $_[0] : {@_};

   for my $param_name (@fields) {
      next unless exists $config->{$param_name};
      $self->{$param_name} = $config->{$param_name};
   }

   $self->set_agent(WWW::Mechanize->new(autocheck => 1, stack_depth => 1, ))
     unless defined $self->get_agent();

   $self->update_proxy(exists($config->{proxy}) && $config->{proxy});

   $self->load_cookies_from($config->{cookie})
     if exists $config->{cookie};
} ## end sub reconfig

sub update_proxy {
   my ($self, $proxy) = @_;
   my $ua = $self->get_agent();
   $ua->env_proxy();
   $ua->proxy('http', $proxy) if $proxy;
   return $proxy;
} ## end sub update_proxy

sub load_cookies_from {
   my $self       = shift;
   my ($filename) = @_;

   require HTTP::Cookies::Mozilla;
   my $jar = HTTP::Cookies::Mozilla->new(autosave => 0);
   $jar->load($filename)
      or croak "could not load cookie file $filename\n";

   # Set photostream_sort_mode to 'recent', trying to be robust
   # getting all the stuff from the currently saved cookie
   my @args;
   $jar->scan(
      sub {
         my ($domain, $name) = @_[4, 1];
         return unless $name eq 'photostream_sort_mode';
         return unless $domain =~ /zooomr/i;
         @args = @_;
      },
   );
   $args[2] = 'recent';    # value
   $jar->set_cookie(@args);

   $self->get_agent()->cookie_jar($jar);

   return;
} ## end sub load_cookies_from

sub login {
   my $self = shift;
   my $args = ref($_[0]) ? $_[0] : {@_};

   $self->set_username($args->{username}) if exists $args->{username};
   $self->set_password($args->{password}) if exists $args->{password};

   my $ua = $self->get_agent();
   $ua->get($self->get_login_page())
      or croak "couldn't get login page\n";
   $ua->form_with_fields(qw( username password ))
      or croak "no login form\n";
   $ua->set_fields(
      username => $self->get_username(),
      password => $self->get_password(),
   );
   $ua->click()
      or croak "no button to click\n";

   return;
} ## end sub login

sub logout {
   my $self = shift;
   return $self->get_agent()->get($self->get_logout_page());
}

sub _config_or_default {
   my $self = shift;
   my $href = shift;
   map {
      if (exists $href->{$_})
      {
         $href->{$_};
      }
      elsif (my $method = $self->can('get_' . $_)) {
         scalar($self->$method());
      }
      else {
         undef;
      }
   } @_;
} ## end sub _config_or_default

sub upload {
   my $self = shift;
   my $config = ref($_[0]) ? $_[0] : {@_};

   my ($updater) = $self->_config_or_default($config, 'updater');
   my $filename  = $config->{filename};
   my $ua        = $self->get_agent();

   (my $barename = file($filename)->basename()) =~ s{\.\w+\z}{}mxs;

   my $updating;
   my $uri = eval {
      $ua->get($self->get_upload_page())
         or croak "couldn't get upload page\n";

      $ua->form_with_fields(qw( Filedata labels is_public ))
         or croak "no form with fields required for upload\n";
      $ua->set_fields(
         labels    => $config->{tags}   || '',
         is_public => $config->{public} || 0,
         Filedata  => $filename,
      );
      $ua->tick('is_friend', 1, $config->{friends});
      $ua->tick('is_family', 1, $config->{family});

      if ($updater) {
         local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD;
         $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
         my $request = $ua->current_form()->click();    # Get request

         my $total = scalar($request->content_length());
         $updater->post(
            'start_file',
            filename     => $filename,
            barename     => $barename,
            file_counter => $config->{file_counter},
            file_octets  => $total,
         );
         $updating = 1;

         my $workhorse = $request->content();
         my $done      = 0;
         $request->content(
            sub {
               my $data_chunk = $workhorse->();
               return unless defined $data_chunk;

               $done += length $data_chunk;
               $updater->post('update_file', sent_octets => $done);

               return $data_chunk;
            },
         );

         $ua->request($request);
      } ## end if ($updater)
      else {
         $ua->click();
      }

      # Check the photo is there
      my $link = $ua->find_link(text => $barename)
         or croak "upload completed but no photo\n";
      $updater->post(
         'end_file',
         filename => $filename,
         uri      => $link->url_abs(),
         outcome  => 'success'
      ) if $updater;
      $link->url_abs();
   };
   return $uri if $uri;

   # Complete stuff in updater before failing
   $updater->post(
      'end_file',
      filename => $filename,
      uri => undef,
      outcome => 'failure',
   ) if $updater && $updating;
   croak $@;
} ## end sub upload

__END__

=head1 NAME

WWW::Zooomr::Scraper - upload files to Zooomr via website interface

=head1 VERSION

This document describes WWW::Zooomr::Scraper version 0.3.0. Most likely, this
version number here is outdate, and you should peek the source.


=head1 SYNOPSIS

   use WWW::Zooomr::Scraper;

   my $zooomr = WWW::Zooomr::Scraper->new();

   eval {
      $zooomr->login(username => 'polettix', password => 'whatever');
      my $photo_uri = $zooomr->upload(filename => '/path/to/file.jpg');
      print {*STDOUT} "URI: $photo_uri\n";
      $zooomr->logout();
   } or warn "error uploading: $@";



=head1 DESCRIPTION

This module allows uploading photos to Zooomr (L<http://www.zooomr.com/>)
programatically through the website interface, i.e. through the same
upload facility that can be used from the browser.

=head1 INTERFACE 

=head2 Object Handling and Configuration

=over

=item B<< new >>

   my $zooomr = WWW::Zooomr::Scraper->new(%config);
   my $zooomr = WWW::Zooomr::Scraper->new(\%config);

Create a new object. The parameters that can be passed are the following:

=over

=item L</updater> 

=item L</agent>

=item L</username>

=item L</password>

=item L</login_page>

=item L</upload_page>

=item L</logout_page>

=back

See the documentation for each corresponding accessor method. Moreover, the
following parameters can be passed (though they do not have accessors):

=over

=item C<proxy>

set the proxy to use for accessing the Internet; this parameter implies setting
the proxy in the L</agent>.

=item C<cookie>

set the cookie file to use in order to gather the access credentials. This
parameter triggers a call to L</load_cookies_from>.

=back

=item B<< reconfig >>

   $zooomr->reconfig(%config);
   $zooomr->reconfig(\%config);

Reconfigures the object with the given configuration - the same parameters
accepted by L</new> can be passed. Additionally, this method sets an
L</agent> if one is not passed or didn't exists previously, and loads the
cookie file if passed.

=item B<< update_proxy >>

   $zooomer->update_proxy($new_proxy_string);

This method reconfigures the proxy in the L</agent> inside the
object. This method can be used to set a new proxy in case of changed
network conditions.

=item B<< load_cookies_from >>

   $zooomr->load_cookies_from($filename);

Load the credentials from the specified cookie file. This is useful if you
want to avoid configuring the L</username> and L</password> parameters; in
this case, you should enter the Zooomr website by yourself, then point the
object to the cookie file produced by your browser, where the connection
credentials are stored.

Note that the Cookie file must have a Mozilla format. SQLite-based system
used by Firefox is OK, as long as L<HTTP::Cookies::Mozilla> is used and
it's a recent-enough version.

=back

=head2 Accessors

The following are accessor methods that give access to objects or
configurations.

=over

=item B<< get_updater >>

=item B<< set_updater >>

The C<updater> is an optional object that is used to provide notifications
to the external world. See the dedicated section L</The Updater> below.

=item B<< get_agent >>

=item B<< set_agent >>

Object a-la L<WWW::Mechanize> that acts as the User-Agent.

For better result, it is suggested that the agent is set in auto-checking mode.

=item B<< get_username >>

=item B<< set_username >>

Username for accessing the Zooomr website and upload photos.

=item B<< get_password >>

=item B<< set_password >>

Password for L</username> at the Zooomr website.

=item B<< get_login_page >>

=item B<< set_login_page >>

The URI of the Zooomr login page. You shouldn't need to set this because
the default value should work out of the box.

=item B<< get_upload_page >>

=item B<< set_upload_page >>

The URI of the Zooomr page for uploading. You shouldn't need to set this
because the default value should work out of the box.

=item B<< get_logout_page >>

=item B<< set_logout_page >>

The URI of the Zooomr logout page. You shouldn't need to set this because
the default value should work out of the box.

=back

=head2 Interaction Methods

=over

=item B<< login >>

   $zooomr->login();
   $zooomr->login(username => 'polettix');
   $zooomr->login(username => 'polettix', password => 'whatever');

Perform the login phase.

Two parameters can be accepted: C<username> and
C<password>, with the same meaning as the accessors. As a matter of fact,
passing either one sets the corresponding value inside the object, i.e. it
calls the accessor for you.

=item B<< logout >>

   $zooomr->logout();

Log out from Zooomr.

=item B<< upload >>

   $zooomr->upload(filename => '/path/to/file.jpg', %other_config);
   $zooomr->upload(\%config);

Add one file to Zooomr. Assumes that the L</login> phase has been performed
successfully.

Returns the URI of the page where the photo can be accessed. Throws an
exception if any error occurs.

The following parameters are supported:

=over

=item C<filename>

mandatory, the name of the photo file to upload;

=item C<tags>

a string with a comma-separated list of tags to associate to the photo;

=item C<public>

flag indicating whether the photo is public (if C<1>) or private (if C<0>);

=item C<friends>

if the L</public> flag above is set to C<0>, you can optionally set that
the photo can be seen by friends;

=item C<family>

if the L</public> flag above is set to C<0>, you can optionally set that
the photo can be seen by family members;

=item C<file_counter>

this is an opaque value that is passed along to the updater, see
L</The Updater>.

=back

=back

=head2 The Updater

You can set an updater object that will be used to track different statuses
of the login/upload processes. In particular, the latter operation can be
long and the User might get nervous without proper feedbak; the updater is
the solution to this problem.

The Updater is something completely optional. If it is set, it must sport
an interface that is specific to the upload phase. The required method
is the following:

=over

=item C<< post >>

   $updater->post($type, %parameters);

Send a specific status message. Possible values for C<$type> are:

=over

=item C<< start_file >>

This event is posted when the file upload starts. In this case, the
parameters that are passed are the following:

=over

=item C<filename>

the full path to the file to be uploaded;

=item C<barename>

the I<bare> name of the file, i.e. the file's basename filename without the
so-called extension. For example, C</path/to/myfile.jpg> has a barename equal
to C<myfile>.

=item C<file_counter>

The same value passed to the C<upload> function.

=item C<file_octets>

The number of octets that will be uploaded, i.e. the Content-Length of
the request soon to be sent.

=back

=item C<< update_file >>

This event is posted at regular intervals to give a feedback about the
upload. Only one parameter is sent, i.e. C<sent_octets>, with the total number
of octets sent (even though the latest chunk is to be sent yet).

=item C<< end_file >>

This event is posted when the file upload ends. The following parameters are
passed:

=over

=item C<filename>

the name of the uploaded file;

=item C<uri>

the URI where the uploaded file is (set to undef if the upload was not
successful);

=item C<outcome>

either C<success> or C<failure>.

=back

=back

=back

The following code represents a minimal but working updater based on
L<Term::ProgressBar>:

   package Some::Updater;
   use strict;
   use warnings;
   use Term::ProgressBar;

   sub post {
      my ($self, $method, %params) = @_;
      $self->$method(%params);
   }

   sub start_file {
      my ($self, %params) = @_;
      $self->{pb} = Term::ProgressBar->new({
         count => $params{file_octets},
         name  => $params{barename},
      });
      $self->{pb} = $pb;
      return;
   }

   sub update_file {
      my ($self, %params) = @_;
      return unless $self->{pb}; # just in case...
      $self->{pb}->update($params{sent_octets});
      return;
   }

   sub update_file {
      my ($self, %params) = @_;
      if ($params{outcome} eq 'failure') {
         print {*STDERR} "something failed with $params{filename}\n";
      }
      else {
         print {*STDERR} "$params{filename} uploaded to $params{uri}\n";
      }
      return;
   }

=head1 DIAGNOSTICS

Some of these errors could be overridden if the User-Agent object is set
to C<auto_check> mode.

=over

=item C<< could't get %s page >>

The specified page (either the login, upload or logout) couldn't be got, so
the related operation bailed out.

This message is overridden by the C<auto_check> mode in the User-Agent.

=item C<< no login form >>

The login page was got, but there is no login form in it. It should indicate
that Zooomr changed the interface.

This message is overridden by the C<auto_check> mode in the User-Agent.

=item C<< no button to click >>

The login form has no button to be clicked. It should indicate that Zooomr
changed the interface.

=item C<< upload completed by no photo >>

The upload process was completed but the photo didn't appear in the User's
default page in Zooomr. This should indicate a failed upload, actually.

=item C<< could not load cookie file %s >>

The cookie file was not accepted by C</load_cookies_from>. It could be
unreadable, or in a non-Mozilla format.

=back


=head1 CONFIGURATION AND ENVIRONMENT

WWW::Zooomr::Scraper requires no configuration files or environment variables.

It honors the C<$ENV{http_proxy}> environment variable when set.


=head1 DEPENDENCIES

This module depends on the following non-core modules:

=over

=item L<version>

=item L<WWW::Mechanize>

=item L<Path::Class>

=back

Additionally, the function L</load_cookies_from> depends upon
C<HTTP::Cookies::Mozilla>.

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests through http://rt.cpan.org/


=head1 AUTHOR

Flavio Poletti  C<< <flavio [at] polettix [dot] it> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Flavio Poletti C<< <flavio [at] polettix [dot] it> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl 5.8.x itself. See L<perlartistic>
and L<perlgpl>.

Questo modulo è software libero: potete ridistribuirlo e/o
modificarlo negli stessi termini di Perl 5.8.x stesso. Vedete anche
L<perlartistic> e L<perlgpl>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=head1 NEGAZIONE DELLA GARANZIA

Poiché questo software viene dato con una licenza gratuita, non
c'è alcuna garanzia associata ad esso, ai fini e per quanto permesso
dalle leggi applicabili. A meno di quanto possa essere specificato
altrove, il proprietario e detentore del copyright fornisce questo
software "così com'è" senza garanzia di alcun tipo, sia essa espressa
o implicita, includendo fra l'altro (senza però limitarsi a questo)
eventuali garanzie implicite di commerciabilità e adeguatezza per
uno scopo particolare. L'intero rischio riguardo alla qualità ed
alle prestazioni di questo software rimane a voi. Se il software
dovesse dimostrarsi difettoso, vi assumete tutte le responsabilità
ed i costi per tutti i necessari servizi, riparazioni o correzioni.

In nessun caso, a meno che ciò non sia richiesto dalle leggi vigenti
o sia regolato da un accordo scritto, alcuno dei detentori del diritto
di copyright, o qualunque altra parte che possa modificare, o redistribuire
questo software così come consentito dalla licenza di cui sopra, potrà
essere considerato responsabile nei vostri confronti per danni, ivi
inclusi danni generali, speciali, incidentali o conseguenziali, derivanti
dall'utilizzo o dall'incapacità di utilizzo di questo software. Ciò
include, a puro titolo di esempio e senza limitarsi ad essi, la perdita
di dati, l'alterazione involontaria o indesiderata di dati, le perdite
sostenute da voi o da terze parti o un fallimento del software ad
operare con un qualsivoglia altro software. Tale negazione di garanzia
rimane in essere anche se i dententori del copyright, o qualsiasi altra
parte, è stata avvisata della possibilità di tali danneggiamenti.

Se decidete di utilizzare questo software, lo fate a vostro rischio
e pericolo. Se pensate che i termini di questa negazione di garanzia
non si confacciano alle vostre esigenze, o al vostro modo di
considerare un software, o ancora al modo in cui avete sempre trattato
software di terze parti, non usatelo. Se lo usate, accettate espressamente
questa negazione di garanzia e la piena responsabilità per qualsiasi
tipo di danno, di qualsiasi natura, possa derivarne.

=head1 SEE ALSO

=for l'autore, da riempire:
   Una lista di moduli/link da considerare per completare le funzionalità
   del modulo, o per trovarne di alternative.

=cut
