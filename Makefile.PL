use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
   NAME          => 'WWW::Zooomr::Scraper',
   AUTHOR        => 'Flavio Poletti <flavio [at] polettix [dot] it>',
   VERSION_FROM  => 'lib/WWW/Zooomr/Scraper.pm',
   ABSTRACT_FROM => 'lib/WWW/Zooomr/Scraper.pm',
   PL_FILES      => {},
   PREREQ_PM     => {
      'Test::More'       => 0,
      'Test::MockObject' => 0,
      'Test::Exception'  => 0,
      'version'          => 0,
      'WWW::Mechanize'   => 0,
      'Path::Class'      => 0,
   },
   dist  => {COMPRESS => 'gzip -9f', SUFFIX => 'gz',},
   clean => {FILES    => 'WWW-Zooomr-Scraper-*'},
);
