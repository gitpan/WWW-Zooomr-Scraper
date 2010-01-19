# vim: filetype=perl :
use strict;
use warnings;

use Test::More tests => 6; # last test to print

use Test::Exception;
use WWW::Zooomr::Scraper;
use Test::MockObject;

my ($username, $password);
if (-e 't/credentials') {
   eval {
      open my $fh, '<', 't/credentials' or die 'whatever'; 
      while (<$fh>) {
         chomp;
         my ($key, $value) = split /\s*=\s*/, $_, 2;
         if ($key eq 'username') {
            $username = $value;
         }
         elsif ($key eq 'password') {
            $password = $value;
         }
      }
   };
}

if (exists $ENV{ZOOOMR_USERNAME}) {
   $username = $ENV{ZOOOMR_USERNAME};
}
if (exists $ENV{ZOOOMR_PASSWORD}) {
   $password = $ENV{ZOOOMR_PASSWORD};
}

SKIP: {
   skip 'no configuration for accessing', 6
      unless defined $username && defined $password;

   my $zooomr;
   lives_ok {
      $zooomr = WWW::Zooomr::Scraper->new();
   }
   'object creation';
   isa_ok($zooomr, 'WWW::Zooomr::Scraper');

   lives_ok {
      $zooomr->login(username => $username, password => $password);
   } 'login';

   my $mock = Test::MockObject->new();
   $mock->set_true('post');

   my $uri;
   lives_ok {
      $uri = $zooomr->upload(filename => 't/prova.jpg');
   } 'upload';
   like($uri, qr{\A http://}mxs, 'URI is a... URI');

   lives_ok {
      $zooomr->logout();
   } 'logout';
} ## end SKIP:
