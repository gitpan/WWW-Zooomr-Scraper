use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
   module_name       => 'WWW::Zooomr::Scraper',
   license           => 'perl',
   dist_author       => 'Flavio Poletti <flavio [at] polettix [dot] it>',
   dist_version_from => 'lib/WWW/Zooomr/Scraper.pm',
   requires          => {
      'Test::More'       => 0,
      'Test::MockObject' => 0,
      'Test::Exception'  => 0,
      'version'          => 0,
      'WWW::Mechanize'   => 0,
      'Path::Class'      => 0,
   },
   add_to_cleanup => ['WWW-Zooomr-Scraper-*'],
);

$builder->create_build_script();
