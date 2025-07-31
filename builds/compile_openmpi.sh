#!/bin/bash -x                                     
#machine_name="gaea" 
#platform="ncrc5.intel23"
#machine_name="tiger" 
#platform="intel18"
#machine_name="googcp" 
#platform="intel19"
#machine_name = "ubuntu"
#platform     = "pgi18"                                             
#machine_name="ubuntu" 
#platform="gnu7"
#machine_name = "gfdl-ws" 
#platform     = "intel15"
#machine_name = "gfdl-ws"
#platform     = "gnu6" 
#machine_name = "theta"   
#platform     = "intel16"
#machine_name="lscsky50"
#platform="intel19up2_avx1" #"intel18_avx1" # "intel18up2_avx1" 
machine_name="tiger3"
platform="tiger3-openmpi" #tiger3-intel, tiger3-openmpi
target="repro" #"debug-openmp"       
flavor="mom6sis2" #mom6sis2, mom6sis2_yaml, fms1_mom6sis2, mom6solo

# compile label for bio or ocean-ice
# be careful with the compile label (clab) here, there are only three options: ocean_ice_bgc, ocean_ice, ocean_only
if [[ $flavor =~ "mom6solo" ]] ; then
   clab='ocean_only'
else
   clab='ocean_ice_bgc'
fi

#can rename the exename
EXENAME="${clab}_20250703"

module purge

module load intel-tbb/2021.13
module load intel-rt/2024.2
module load intel-oneapi/2024.2
module load openmpi/oneapi-2024.2/4.1.8
module load hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4
module load netcdf/oneapi-2024.2/hdf5-1.14.4/openmpi-4.1.6/4.9.2
#module load intel-mpi/oneapi/2021.13
#module load hdf5/oneapi-2024.2/intel-mpi/1.14.4
#module load netcdf/oneapi-2024.2/hdf5-1.14.4/intel-mpi/4.9.2
export OMPI_F90=ifort
export OMPI_FC=ifort

usage()
{
    #echo "usage: linux-build.bash -m googcp -p intel19 -t prod -f mom6sis2"
    #echo "usage: ./linux-build.bash -m stellar-amd -p stellar-amd -t prod -f mom6sis2"
    echo "usage: ./compile_mom6.sh -m $machine_name -p $platform -t $target -f $flavor -c $clab"
}

# parse command-line arguments
while getopts "m:p:t:f:c:h" Option
do
   case "$Option" in
      m) machine_name=${OPTARG};;
      p) platform=${OPTARG} ;;
      t) target=${OPTARG} ;;
      f) flavor=${OPTARG} ;;
      c) clab=${OPTARG} ;;
      h) usage ; exit ;;
   esac
done

rootdir=`dirname $0`
abs_rootdir=`cd $rootdir && pwd`


#load modules              
source $MODULESHOME/init/bash
source $rootdir/$machine_name/$platform.env
. $rootdir/$machine_name/$platform.env

#makeflags="NETCDF=3 AVX=512 -j56 "
makeflags="NETCDF=4"

if [[ $target =~ "repro" ]] ; then
   makeflags="$makeflags REPRO=1"
fi

if [[ $target =~ "prod" ]] ; then
   makeflags="$makeflags PROD=1"
fi

if [[ $target =~ "avx512" ]] ; then
   makeflags="$makeflags PROD=1 AVX=512"
fi

if [[ $target =~ "debug" ]] ; then
   makeflags="$makeflags DEBUG=1"
fi

srcdir=$abs_rootdir/../src

sed -i 's/static pid_t gettid(void)/pid_t gettid(void)/g' $srcdir/FMS/affinity/affinity.c

if [[ $flavor == "mom6sis2" ]] ; then

    mkdir -p build/$machine_name-$platform/$EXENAME/shared/$target
    pushd build/$machine_name-$platform/$EXENAME/shared/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/FMS/{affinity,amip_interp,column_diagnostics,diag_integral,drifters,horiz_interp,memutils,sat_vapor_pres,topography,astronomy,constants,diag_manager,field_manager,include,monin_obukhov,platform,tracer_manager,axis_utils,coupler,fms,fms2_io,interpolator,grid_utils,mosaic2,random_numbers,time_interp,tridiagonal,block_control,data_override,exchange,mpp,time_manager,string_utils,parser}/ $srcdir/FMS/libFMS.F90
    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -p libfms.a -c "-Duse_libMPI -Duse_netCDF -DMAXFIELDMETHODS_=800" path_names

    make $makeflags libfms.a

    if [ $? -ne 0 ]; then
        echo "Could not build the FMS library!"
        exit 1
    fi

    popd
    
    mkdir -p build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    pushd build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/MOM6/{config_src/infra/FMS2,config_src/memory/dynamic_symmetric,config_src/drivers/FMS_cap,config_src/external/MARBL,config_src/external/ODA_hooks,config_src/external/database_comms,config_src/external/drifters,config_src/external/stochastic_physics,pkg/GSW-Fortran/{modules,toolbox}/,src/{*,*/*}/} $srcdir/SIS2/{config_src/dynamic_symmetric,config_src/external/Icepack_interfaces,src} $srcdir/icebergs/src $srcdir/FMS/{coupler,include}/ $srcdir/{ocean_BGC/generic_tracers,ocean_BGC/generic_fluxes,ocean_BGC/mocsy/src}/ $srcdir/{atmos_null,ice_param,land_null,coupler/shared/,coupler/full/}/


    compiler_options='-DINTERNAL_FILE_NML -DUSE_FMS2_IO -DMAX_FIELDS_=600 -DNOT_SET_AFFINITY -D_USE_MOM6_DIAG -D_USE_GENERIC_TRACER -DUSE_PRECISION=2 -D_USE_LEGACY_LAND_ -Duse_AM3_physics'
    linker_options=''
    if [[ "$target" =~ "stdpar" ]] ; then 
        compiler_options="$compiler_options -stdpar -Minfo=accel"
        linker_options="$linker_options -stdpar "
    fi

    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -o "-I../../shared/$target" -p $EXENAME -l "-L../../shared/$target -lfms $linker_options" -c "$compiler_options" path_names

    make $makeflags $EXENAME

elif [[ $flavor == "mom6sis2_yaml" ]]; then

    echo "build mom6sis2 with FMS2 cap and yaml"

    [[ -d build/$machine_name-$platform/$EXENAME/libyaml/$target ]] && rm -rf build/$machine_name-$platform/$EXENAME/libyaml/$target
    mkdir -p build/$machine_name-$platform/$EXENAME/libyaml/$target
    pushd $srcdir/libyaml
    $srcdir/libyaml/bootstrap
    $srcdir/libyaml/configure --prefix=$abs_rootdir/build/$machine_name-$platform/$EXENAME/libyaml/$target 
    make 
    make install

    if [ $? -ne 0 ]; then
        echo "Could not build the libyaml library!"
        exit 1
    fi
    popd

    mkdir -p build/$machine_name-$platform/$EXENAME/shared/$target
    pushd build/$machine_name-$platform/$EXENAME/shared/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/FMS/{affinity,amip_interp,column_diagnostics,diag_integral,drifters,horiz_interp,memutils,sat_vapor_pres,topography,astronomy,constants,diag_manager,field_manager,include,monin_obukhov,platform,tracer_manager,axis_utils,coupler,fms,fms2_io,interpolator,grid_utils,mosaic2,random_numbers,time_interp,tridiagonal,block_control,data_override,exchange,mpp,time_manager,string_utils,parser}/ $srcdir/FMS/libFMS.F90
    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -o "-I../../libyaml/$target/include" -p libfms.a -l "-L../../libyaml/$target/lib -lyaml $linker_options" -c "-Duse_libMPI -Duse_yaml -Duse_netCDF -DMAXFIELDMETHODS_=800" path_names

    make $makeflags libfms.a

    if [ $? -ne 0 ]; then
        echo "Could not build the FMS library!"
        exit 1
    fi

    popd

    mkdir -p build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    pushd build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/MOM6/{config_src/infra/FMS2,config_src/memory/dynamic_symmetric,config_src/drivers/FMS_cap,config_src/external/MARBL,config_src/external/ODA_hooks,config_src/external/database_comms,config_src/external/drifters,config_src/external/stochastic_physics,pkg/GSW-Fortran/{modules,toolbox}/,src/{*,*/*}/} $srcdir/SIS2/{config_src/dynamic_symmetric,config_src/external/Icepack_interfaces,src} $srcdir/icebergs/src $srcdir/FMS/{coupler,include}/ $srcdir/{ocean_BGC/generic_tracers,ocean_BGC/generic_fluxes,ocean_BGC/mocsy/src}/ $srcdir/{atmos_null,ice_param,land_null,coupler/shared/,coupler/full/}/


    compiler_options='-DINTERNAL_FILE_NML -DUSE_FMS2_IO -Duse_yaml -DMAX_FIELDS_=600 -DNOT_SET_AFFINITY -D_USE_MOM6_DIAG -D_USE_GENERIC_TRACER -DUSE_PRECISION=2 -D_USE_LEGACY_LAND_ -Duse_AM3_physics'
linker_options=''
    if [[ "$target" =~ "stdpar" ]] ; then
        compiler_options="$compiler_options -stdpar -Minfo=accel"
        linker_options="$linker_options -stdpar "
    fi

    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -o "-I../../shared/$target -I../../libyaml/$target/include" -p $EXENAME -l "-L../../shared/$target -lfms -L../../libyaml/$target/lib -lyaml $linker_options" -c "$compiler_options" path_names

    make $makeflags $EXENAME

elif [[ $flavor == "fms1_mom6sis2" ]]; then

    echo "build mom6sis2 with FMS1 cap" 

    mkdir -p build/$machine_name-$platform/$EXENAME/shared/$target
    pushd build/$machine_name-$platform/$EXENAME/shared/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/FMS/{affinity,amip_interp,column_diagnostics,diag_integral,drifters,horiz_interp,memutils,sat_vapor_pres,topography,astronomy,constants,diag_manager,field_manager,include,monin_obukhov,platform,tracer_manager,axis_utils,coupler,fms,fms2_io,interpolator,grid_utils,mosaic2,random_numbers,time_interp,tridiagonal,block_control,data_override,exchange,mpp,time_manager,string_utils,parser}/ $srcdir/FMS/libFMS.F90
    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -p libfms.a -c "-Duse_deprecated_io -Duse_libMPI -Duse_netCDF -DMAXFIELDMETHODS_=800" path_names

    make $makeflags libfms.a

    if [ $? -ne 0 ]; then
        echo "Could not build the FMS library!"
        exit 1
    fi

    popd

    mkdir -p build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    pushd build/$machine_name-$platform/$EXENAME/ocean_ice/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/MOM6/{config_src/infra/FMS1,config_src/memory/dynamic_symmetric,config_src/drivers/FMS_cap,config_src/external/MARBL,config_src/external/ODA_hooks,config_src/external/database_comms,config_src/external/drifters,config_src/external/stochastic_physics,pkg/GSW-Fortran/{modules,toolbox}/,src/{*,*/*}/} $srcdir/SIS2/{config_src/dynamic_symmetric,config_src/external/Icepack_interfaces,src} $srcdir/icebergs/src $srcdir/FMS/{coupler,include}/ $srcdir/{ocean_BGC/generic_tracers,ocean_BGC/generic_fluxes,ocean_BGC/mocsy/src}/ $srcdir/{atmos_null,ice_param,land_null,coupler/shared/,coupler/full/}/


    compiler_options='-DINTERNAL_FILE_NML -DMAX_FIELDS_=600 -DNOT_SET_AFFINITY -Duse_deprecated_io -D_USE_MOM6_DIAG -D_USE_GENERIC_TRACER -DUSE_PRECISION=2 -D_USE_LEGACY_LAND_ -Duse_AM3_physics'
    linker_options=''
    if [[ "$target" =~ "stdpar" ]] ; then
        compiler_options="$compiler_options -stdpar -Minfo=accel"
        linker_options="$linker_options -stdpar "
    fi

    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -o "-I../../shared/$target" -p $EXENAME -l "-L../../shared/$target -lfms $linker_options" -c "$compiler_options" path_names

    make $makeflags $EXENAME

else 

    echo "build mom6 solo"

    mkdir -p build/$machine_name-$platform/$EXENAME/shared/$target
    pushd build/$machine_name-$platform/$EXENAME/shared/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/FMS/{affinity,amip_interp,column_diagnostics,diag_integral,drifters,horiz_interp,memutils,sat_vapor_pres,topography,astronomy,constants,diag_manager,field_manager,include,monin_obukhov,platform,tracer_manager,axis_utils,coupler,fms,fms2_io,interpolator,grid_utils,mosaic2,random_numbers,time_interp,tridiagonal,block_control,data_override,exchange,mpp,time_manager,string_utils,parser}/ $srcdir/FMS/libFMS.F90
$srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -p libfms.a -c "-Duse_libMPI -Duse_netCDF -DMAXFIELDMETHODS_=800" path_names

    make $makeflags libfms.a

    if [ $? -ne 0 ]; then
        echo "Could not build the FMS library!"
        exit 1
    fi

    popd

    mkdir -p build/$machine_name-$platform/$EXENAME/ocean_only/$target
    pushd build/$machine_name-$platform/$EXENAME/ocean_only/$target
    rm -f path_names
    $srcdir/mkmf/bin/list_paths $srcdir/MOM6/{config_src/infra/FMS2,config_src/memory/dynamic_symmetric,config_src/drivers/solo_driver,config_src/external/GFDL_ocean_BGC,config_src/external/MARBL,config_src/external/ODA_hooks,config_src/external/database_comms,config_src/external/drifters,config_src/external/stochastic_physics,pkg/GSW-Fortran/{modules,toolbox}/,src/{*,*/*}}/
    $srcdir/mkmf/bin/mkmf -t $abs_rootdir/$machine_name/$platform.mk -o "-I../../shared/$target" -p $EXENAME -l "-L../../shared/$target -lfms" -c '-Duse_netCDF -DSPMD' path_names

    make $makeflags $EXENAME
fi
