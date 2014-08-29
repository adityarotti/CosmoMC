    module CosmoTheory
    use settings
    use CosmologyTypes
    use GeneralTypes
    use likelihood
    use Interpolation
    implicit none
    private

    Type, extends(TInterpGrid2D) :: TCosmoTheoryPK
        !whether power is stored as log(P_k)
        logical :: islog = .true.
    contains
    procedure :: PowerAt
    end Type TCosmoTheoryPK

    Type TSkyPowerSpectrum
        real(mcp), allocatable :: CL(:)
    end Type TSkyPowerSpectrum

    Type, extends(TTheoryPredictions) :: TCosmoTheoryPredictions
        Type(TSkyPowerSpectrum), allocatable :: Cls(:,:)
        !(this, E, B, Phi) x (this, E, B, Phi), with L(L+1)/2pi factor, in muK for CMB components
        real(mcp) sigma_8
        real(mcp) tensor_ratio_C10, tensor_ratio_02, tensor_ratio_BB, tensor_AT
        integer numderived
        real(mcp) derived_parameters(max_derived_parameters)
        !MPK's are interpolator objects now
        !MPK%x = logkh, MPK%y = z (redshift), MPK%z =>actual data array
        !MPK%nx = num_k, MPK%ny = num_z
        type(TCosmoTheoryPK), allocatable :: MPK
        type(TCosmoTheoryPK), allocatable :: NL_MPK
    contains
    procedure :: FreePK
    procedure :: ClArray
    procedure :: ClsAtL
    procedure :: WriteTextCls
    procedure :: AllocateForSettings => TCosmoTheoryPredictions_AllocateForSettings
    !Inherited overrides
    procedure :: WriteTheory => TCosmoTheoryPredictions_WriteTheory
    procedure :: ReadTheory => TCosmoTheoryPredictions_ReadTheory
    procedure :: WriteTextData => TCosmoTheoryPredictions_WriteTextData
    end Type TCosmoTheoryPredictions

    public TCosmoTheoryPredictions, TCosmoTheoryPK,  TSkyPowerSpectrum
    contains

    function PowerAt(PK,k,z) result(outpower)
    class(TCosmoTheoryPK) PK
    real(mcp), intent(in) :: k,z
    real(mcp) :: logk
    real(mcp) :: outpower

    logk=log(k)
    if(.not. allocated(PK%x)) then
        write(*,*) 'ERROR:  PowerAt least one of your PK arrays is not initialized:'
        write(*,*) '        Make sure you are calling a SetPk and filling your power spectra.'
        write(*,*) '        This error could also mean you are doing importance sampling'
        write(*,*) '        and need to turn on redo_pk.'
        call MPIstop()
    end if

    if(PK%islog) then
        outpower = exp(PK%Value(logk,z))
    else
        outpower = PK%Value(logk,z)
    end if

    end function PowerAt

    subroutine FreePK(this)
    class(TCosmoTheoryPredictions) this

    if(allocated(this%MPK))deallocate(this%MPK)
    if(allocated(this%NL_MPK)) deallocate(this%NL_MPK)

    end subroutine FreePK

    subroutine ClArray(this, cl, i, j)
    class(TCosmoTheoryPredictions) this
    real(mcp) :: cl(1:)
    integer i, j, ii,jj,outmax, inmax,mx

    if (j>i) then
        jj=i
        ii=j
    else
        ii=i
        jj=j
    end if
    if (allocated(this%Cls(ii,jj)%Cl)) then
        outmax = size(cl)
        inmax = size(this%Cls(ii,jj)%Cl)
        mx = min(outmax,inmax)
        cl(1:mx) = this%Cls(ii,jj)%Cl(1:mx)
        cl(mx+1:outmax)=0
    else
        call MpiStop('CosmoTheory: ClArray not calcualated')
    end if

    end subroutine ClArray


    subroutine ClsAtL(this, L, cl, max_ix_out)
    !TT EE TE BB BE BT PP.. order
    class(TCosmoTheoryPredictions) this
    real(mcp):: cl(:)
    integer, intent(in) :: L
    integer, intent(in), optional ::max_ix_out
    integer imax,ix,i,j, inmax

    imax = PresentDefault(size(this%Cls,2),max_ix_out)
    ix=0
    do i=1,min(size(this%Cls,2),imax)
        do j= i, 1, -1
            ix = ix+1
            if (allocated(this%Cls(i,j)%CL)) then
                inmax = size(this%Cls(i,j)%Cl)
                if (inmax >= L) then
                    cl(ix) = this%Cls(i,j)%Cl(L)
                else
                    cl(ix)=0
                end if
            else
                cl(ix) = 0
            end if
        end do
    end do

    end subroutine ClsAtL


    subroutine WriteTextCls(this,aname)
    class(TCosmoTheoryPredictions) this
    character (LEN=*), intent(in) :: aname
    integer l
    real(mcp), allocatable :: cl(:,:)
    Type(TTextFile) :: F
    character(LEN=*), parameter :: fmt = '(1I6,*(E15.5))'
    integer i, j, n, ix
    character(LEN=:), allocatable :: fields

    n = count(CosmoSettings%cl_lmax>0)
    allocate(cl(CosmoSettings%lmax,n), source=0._mcp)
    ix=0
    fields = '#    L    '
    do i = 1, size(this%Cls,2)
        do j=1,i
            if (CosmoSettings%cl_lmax(i,j)>0) then
                ix=ix+1
                call this%ClArray(cl(:,ix),i,j)
                fields = fields // CMB_CL_Fields(j:j)//CMB_CL_Fields(i:i)//'             '
            end if
        end do
    end do

    call F%CreateFile(aname)
    call F%WriteTrim(fields)
    do l = 2, CosmoSettings%lmax
        write(F%unit,fmt) L,cl(L,:)
    end do
    call F%Close()

    end subroutine WriteTextCls

    subroutine TCosmoTheoryPredictions_WriteTheory(this, F, first)
    Class(TCosmoTheoryPredictions) this
    class(TFileStream) :: F
    logical, intent(in) :: first
    integer tmp(0)
    integer i,j

    if (first .and. new_chains) then
        Write(F%Unit) CosmoSettings%TCosmoTheoryParams
        if (CosmoSettings%use_LSS) call F%WriteSizedArray(CosmoSettings%power_redshifts)
        if (CosmoSettings%use_CMB) call F%WriteSizedArray(CosmoSettings%cl_lmax)
        call F%WriteSizedArray(tmp)
    end if

    write(F%unit) this%numderived
    write(F%unit) this%derived_parameters(1:this%numderived)
    do i=1,CosmoSettings%num_cls
        do j= i, 1, -1
            if (CosmoSettings%cl_lmax(i,j)>0) then
                call F%WriteSizedArray(this%Cls(i,j)%Cl)
            end if
        end do
    end do

    if (CosmoSettings%compute_tensors) then
        write(F%unit) this%tensor_ratio_02, this%tensor_ratio_C10, this%tensor_ratio_BB, this%tensor_AT
    end if

    if (CosmoSettings%get_sigma8 .or. CosmoSettings%use_LSS) write(F%unit) this%sigma_8

    if (CosmoSettings%use_LSS) then
        write(F%unit) this%MPK%nx, this%MPK%ny
        write(F%unit) this%MPK%x
        write(F%unit) this%MPK%y
        write(F%unit) this%MPK%z
        if(CosmoSettings%use_nonlinear) write(F%unit) this%NL_MPK%z
    end if

    end subroutine TCosmoTheoryPredictions_WriteTheory

    subroutine TCosmoTheoryPredictions_AllocateForSettings(this, Settings)
    Class(TCosmoTheoryPredictions) this
    class(TCosmoTheorySettings):: Settings
    integer i,j

    if (allocated(this%Cls)) deallocate(this%Cls)
    allocate(this%Cls(Settings%num_cls,Settings%num_cls))
    do i=1,Settings%num_cls
        do j= i, 1, -1
            if (Settings%cl_lmax(i,j) >0) &
            & allocate(this%Cls(i,j)%Cl(Settings%cl_lmax(i,j)), source=0._mcp)
        end do
    end do
    end subroutine TCosmoTheoryPredictions_AllocateForSettings


    subroutine TCosmoTheoryPredictions_ReadTheory(this, F, first)
    Class(TCosmoTheoryPredictions) this
    class(TFileStream) :: F
    logical, intent(in) :: first
    type(TCosmoTheorySettings), save :: FileSettings
    !JD 02/14 new variables for handling new pk arrays
    integer :: num_k, num_z
    real(mcp), allocatable :: temp(:,:)
    real(mcp), allocatable :: k(:), z(:)
    real(mcp), allocatable :: cl(:)
    integer, allocatable :: tmp(:)
    integer i,j

    if (first) then
        read(F%Unit) FileSettings%TCosmoTheoryParams
        if (FileSettings%use_LSS) call F%ReadSizedArray(FileSettings%power_redshifts)
        if (FileSettings%use_CMB) call F%ReadSizedArray(FileSettings%cl_lmax)
        call F%ReadSizedArray(tmp) !not used
    end if

    call this%AllocateForSettings(CosmoSettings)
    this%derived_parameters=0
    read(F%unit) this%numderived
    read(F%unit) this%derived_parameters(1:this%numderived)

    do i=1,FileSettings%num_cls
        do j= i, 1, -1
            if (FileSettings%cl_lmax(i,j)>0) then
                call F%ReadSizedArray(cl)
                if (CosmoSettings%cl_lmax(i,j)>0) then
                    associate (Sz => min(FileSettings%cl_lmax(i,j),CosmoSettings%cl_lmax(i,j)))
                        this%Cls(i,j)%Cl(1:Sz) = Cl(1:sz)
                        end associate
                end if
                deallocate(cl)
            end if
        end do
    end do

    if (FileSettings%compute_tensors) then
        read(F%unit) this%tensor_ratio_02, this%tensor_ratio_C10, this%tensor_ratio_BB, this%tensor_AT
    end if

    if (FileSettings%get_sigma8 .or. FileSettings%use_LSS) read(F%unit) this%sigma_8
    if (FileSettings%use_LSS) then
        if (CosmoSettings%use_LSS) then
            if (any(FileSettings%power_redshifts/=CosmoSettings%power_redshifts)) &
            & call MpiStop('TCosmoTheoryPredictions_ReadTheory: power_redshifts differ - check')
        end if
        call this%FreePK()
        allocate(this%MPK)
        read(F%unit) num_k, num_z
        allocate(temp(num_k,num_z))
        allocate(k(num_k))
        allocate(z(num_z))
        read(F%unit) k
        read(F%unit) z
        read(F%unit) temp
        call this%MPK%Init(k,z,temp)
        if(FileSettings%use_nonlinear) then
            allocate(this%NL_MPK)
            read(F%unit)temp
            call this%NL_MPK%Init(k,z,temp)
            if(.not. CosmoSettings%use_nonlinear) then
                write(*,*)"WARNING:  ReadTheory - Your data files have nonlinear power spectra,"
                write(*,*)"          but you are not using them. Be careful that this"
                write(*,*)"          is what you intended."
            end if
        end if
    end if

    end subroutine TCosmoTheoryPredictions_ReadTheory

    subroutine TCosmoTheoryPredictions_WriteTextData(this,fnameroot)
    class(TCosmoTheoryPredictions) this
    character(LEN=*), intent(in) :: fnameroot

    if (CosmoSettings%use_CMB) call this%WriteTextCls(fnameroot //'.theory_cl')

    end subroutine TCosmoTheoryPredictions_WriteTextData

    end module CosmoTheory
