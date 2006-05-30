use Module::Build;

my $build = Module::Build->new(
    module_name        => 'Class::Meta::Express',
    license            => 'perl',
    requires           => {
        Class::Meta  => '0',
    },
    build_requires     => { Test::Simple  => '0.17' },
    create_makefile_pl => 'passthrough',
);
$build->create_build_script;
