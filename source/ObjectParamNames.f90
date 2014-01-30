    module ParamNames
    use AmlUtils
    use FileUtils
    implicit none

    integer, parameter :: ParamNames_maxlen = 128

    Type TParamNames
        integer :: nnames =0
        integer :: num_MCMC = 0
        integer :: num_derived = 0
        character(LEN=ParamNames_maxlen), dimension(:), pointer ::  name=> null()
        character(LEN=ParamNames_maxlen), dimension(:), pointer ::  label => null()
        character(LEN=ParamNames_maxlen), dimension(:), pointer ::  comment => null()
        logical, dimension(:), pointer ::  is_derived
    contains
    procedure :: Add => ParamNames_Add
    procedure :: Alloc => ParamNames_Alloc
    procedure :: AssignItem => ParamNames_AssignItem
    procedure :: AsString => ParamNames_AsString
    procedure :: Dealloc => ParamNames_Dealloc
    procedure :: HasReadIniForParam => ParamNames_HasReadIniForParam
    procedure :: Index => ParamNames_Index
    procedure :: Init => ParamNames_Init
    procedure :: LabelForName => ParamNames_label
    procedure :: MaxNameLen => ParamNames_MaxNameLen
    procedure :: NameAtIndex => ParamNames_name
    procedure :: NameOrNumber => ParamNames_NameOrNumber
    procedure :: ParseLine => ParamNames_ParseLine
    procedure :: ReadIndices => ParamNames_ReadIndices
    procedure :: ReadIniForParam => ParamNames_ReadIniForParam
    procedure :: SetLabels => ParamNames_SetLabels
    procedure :: WriteFile => ParamNames_WriteFile
    end Type TParamNames

    contains

    function IsWhiteSpace(C)
    character, intent(in) :: C
    logical IsWhiteSpace

    IsWhiteSpace = (C==' ') .or. (C==char(9))

    end function IsWhiteSpace


    function ParamNames_ParseLine(Names,InLine,n) result(res)
    class(TParamNames) :: Names
    character(LEN=*) :: InLine
    integer n
    logical res
    integer pos, len

    len = len_trim(InLIne)
    pos =1
    do while (pos < len .and. IsWhiteSpace(InLIne(pos:pos)))
        pos = pos+1
    end do
    read(InLine(pos:), *, end=400, err=400) Names%name(n)
    pos = pos + len_trim(Names%name(n))
    do while (pos < len .and. IsWhiteSpace(InLIne(pos:pos)))
        pos = pos+1
    end do
    Names%label(n) = trim(adjustl(InLine(pos:len)))
    pos = scan(Names%label(n),'#')
    if (pos/=0) then
        Names%comment(n) = Names%label(n)(pos+1: len_trim(Names%label(n)))
        Names%label(n) = Names%label(n)(1:pos-1)
    else
        Names%comment(n) = ''
    endif
    pos = scan(Names%label(n),char(9))
    if (pos/=0) Names%label(n) = Names%label(n)(1:pos-1)
    Names%name(n) = trim(adjustl(Names%name(n)))
    len = len_trim( Names%name(n) )
    if (Names%name(n)(len:len)=='*') then
        Names%name(n)(len:len)=' '
        Names%is_derived(n) = .true.
    else
        Names%is_derived(n) = .false.
    end if
    res = .true.
    return
400 res=.false.
    return

    end function ParamNames_ParseLine

    subroutine ParamNames_Alloc(Names,n)
    class(TParamNames) :: Names
    integer,intent(in) :: n

    allocate(Names%name(n))
    allocate(Names%label(n))
    allocate(Names%comment(n))
    allocate(Names%is_derived(n))
    Names%nnames = n
    Names%is_derived = .false.
    Names%num_MCMC = 0
    Names%num_derived = 0
    Names%name = ''
    Names%comment=''
    Names%label=''

    end subroutine ParamNames_Alloc

    subroutine ParamNames_dealloc(Names)
    class(TParamNames) :: Names
    if (associated(Names%name)) &
    deallocate(Names%name,Names%label,Names%comment,Names%is_derived)

    end subroutine ParamNames_dealloc

    subroutine ParamNames_Init(Names, filename)
    class(TParamNames) :: Names
    character(Len=*), intent(in) :: filename
    integer handle,n, status
    character (LEN=ParamNames_maxlen*3) :: InLine

    handle = OpenNewTxtFile(filename)
    n = FileLines(handle)
    call Names%Alloc(n)

    n=0
    do
        if (.not. ReadLine(handle, Inline)) exit
        if (trim(InLine)=='') cycle
        n=n+1
        if (.not. Names%ParseLine(InLine,n)) then
            call MpiStop(concat('ParamNames_Init: error parsing line: ',n))
        end if
    end do

    close(handle)

    Names%nnames = n
    Names%num_derived = count(Names%is_derived)
    Names%num_MCMC = Names%nnames - Names%num_derived


    end subroutine ParamNames_Init

    subroutine ParamNames_AssignItem(Names, Names2,n,i)
    class(TParamNames), target :: Names, Names2
    integer n, i

    Names%name(n) = Names2%name(i)
    Names%label(n) = Names2%label(i)
    Names%comment(n) = Names2%comment(i)
    Names%is_derived(n) = Names2%is_derived(i)

    end subroutine ParamNames_AssignItem

    subroutine ParamNames_Add(Names, Names2)
    class(TParamNames), target :: Names, Names2
    integer n,i, newold, derived
    class(TParamNames),pointer :: P, NamesOrig

    allocate(NamesOrig, source = Names)

    n=0
    do i=1, names2%nnames
        if (NamesOrig%index(Names2%name(i))==-1) then
            n=n+1
        end if
    end do
    if (n==0) return

    call Names%Alloc(NamesOrig%nnames + n)
    Names%nnames = 0
    do derived=0,1
        P=> NamesOrig
        do newold=0,1
            do i=1, P%nnames
                if (Names%index(P%name(i))==-1) then
                    if (derived==0 .and. .not. P%is_derived(i) .or.derived==1 .and. P%is_derived(i) ) then
                        Names%nnames = Names%nnames + 1
                        call Names%AssignItem(P, Names%nnames , i)
                    end if
                end if
            end do
            P=> Names2
        enddo
    end do
    if (Names%nnames/= NamesOrig%nnames + n) stop 'ParamNames_Add: duplicate parameters?'

    Names%num_derived = count(Names%is_derived)
    Names%num_MCMC= Names%nnames-Names%num_derived

    call NamesOrig%Dealloc()
    deallocate(NamesOrig)

    end subroutine ParamNames_Add

    subroutine ParamNames_SetLabels(Names,filename)
    class(TParamNames) :: Names
    Type(TParamNames) :: LabNames
    character(Len=*), intent(in) :: filename
    integer i,ix

    call LabNames%init(filename)
    do i=1, LabNames%nnames
        ix = Names%index(LabNames%name(i))
        if (ix/=-1) then
            Names%label(ix) = LabNames%label(i)
        end if
    end do

    end subroutine ParamNames_SetLabels

    function ParamNames_index(Names,name) result(ix)
    class(TParamNames) :: Names
    character(len=*), intent(in) :: name
    integer ix,i

    do i=1,Names%nnames
        if (Names%name(i) == name) then
            ix = i
            return
        end if
    end do
    ix = -1

    end function ParamNames_index


    function ParamNames_label(Names,name) result(lab)
    class(TParamNames) :: Names
    character(len=*), intent(in) :: name
    character(len = ParamNames_maxlen) lab
    integer ix

    ix = Names%index(name)
    if (ix>0) then
        lab = Names%label(ix)
    else
        lab = ''
    end if

    end function ParamNames_label

    function ParamNames_name(Names,ix) result(name)
    class(TParamNames) :: Names
    character(len=ParamNames_maxlen)  :: name
    integer, intent(in) :: ix

    if (ix <= Names%nnames) then
        name = Names%name(ix)
    else
        name = ''
    end if

    end function ParamNames_name


    subroutine ParamNames_ReadIndices(Names,InLine, params, num, unknown_value)
    class(TParamNames) :: Names
    character(LEN=*), intent(in) :: InLine
    integer, intent(out) :: params(*)
    integer, intent(in), optional :: unknown_value
    integer  :: num
    character(LEN=ParamNames_maxlen) part
    integer param,len,ix, pos, max_num, outparam, outvalue
    integer, parameter :: unknown_num = 1024
    character(LEN=1024) :: skips

    skips=''
    if (num==0) return
    len = len_trim(InLine)
    pos = 1
    if (num==-1) then
        max_num = unknown_num
    else
        max_num = num
    end if
    outparam=0
    do param = 1, max_num
        do while (pos < len .and. IsWhiteSpace(InLine(pos:pos)))
            pos = pos+1
        end do
        read(InLine(pos:), *, end=400, err=400) part
        pos = pos + len_trim(part)
        ix = Names%index(part)
        if (ix>0) then
            outvalue = ix
        else
            if (verify(trim(part),'0123456789') /= 0) then
                if (present(unknown_value)) then
                    skips = trim(skips)//' '//trim(part)
                    if (unknown_value/=-1) then
                        outvalue = unknown_value
                    else
                        cycle
                    end if
                else
                    call MpiStop( 'ParamNames: Unknown parameter name '//trim(part))
                end if
            else
                read(part,*) outvalue
            end if
        end if
        outparam = outparam +1
        if (max_num == unknown_num) num = outparam
        params(outparam) = outvalue
    end do
    return
400 if (skips/='') write(*,'(a)') ' skipped unused params:'//trim(skips)
    if (max_num==unknown_num) return
    call MpiStop('ParamNames: Not enough names or numbers - '//trim(InLine))

    end subroutine ParamNames_ReadIndices

    function ParamNames_AsString(Names, i, want_comment) result(line)
    class(TParamNames) :: Names
    integer, intent(in) :: i
    logical ,intent(in), optional :: want_comment
    character(LEN=ParamNames_maxlen*3) Line
    logical wantCom

    if (present(want_comment)) then
        wantCom = want_comment
    else
        wantCom = .false.
    end if

    if (i> Names%nnames) call MpiStop('ParamNames_AsString: index out of range')
    Line = trim(Names%name(i))
    if (Names%is_derived(i))Line = concat(Line,'*')
    Line =  trim(Line)//char(9)//trim(Names%label(i))
    if (wantCom .and. Names%comment(i)/='') then
        Line = trim(Line)//char(9)//'#'//trim(Names%comment(i))
    end if

    end function ParamNames_AsString

    subroutine ParamNames_WriteFile(Names, fname, indices, add_derived)
    class(TParamNames) :: Names
    character(LEN=*), intent(in) :: fname
    integer, intent(in), optional :: indices(:)
    logical, intent(in), optional :: add_derived
    integer :: unit
    integer i

    unit = CreateNewTxtFile(fname)
    if (present(indices)) then
        do i=1, size(indices)
            write(unit,*) trim(Names%AsString(indices(i)))
        end do
        if (present(add_derived)) then
            if (add_derived) then
                do i=1,Names%num_derived
                    write(unit,*) trim(Names%AsString(Names%num_mcmc+i))
                end do
            end if
        end if
    else
        do i=1, Names%nnames
            write(unit,*) trim(Names%AsString(i))
        end do
    end if

    close(unit)

    end subroutine ParamNames_WriteFile


    function ParamNames_NameOrNumber(Names,ix) result(name)
    class(TParamNames) :: Names
    character(len=ParamNames_maxlen)  :: name
    integer, intent(in) :: ix

    name = Names%name(ix)
    if (name == '') name = IntToStr(ix)

    end function ParamNames_NameOrNumber

    function ParamNames_MaxNameLen(Names) result(len)
    class(TParamNames) :: Names
    integer len, i

    len = 0
    do i=1, Names%nnames
        len = max(len, len_trim(Names%NameOrNumber(i)))
    end do

    end function ParamNames_MaxNameLen

    subroutine ParamNames_WriteMatlab(Names,  unit, headObj)
    class(TParamNames) :: Names
    character(len=ParamNames_maxlen) name
    character(len=*), intent(in) :: headObj
    integer :: unit
    integer i

    do i=1, Names%nnames
        name = Names%name(i)
        if (name /= '') then
            write(unit,'(a)', advance='NO') trim(headObj)//trim(name)//'= struct(''n'','''//trim(name) &
            //''',''i'','//trim(intToStr(i))//',''label'','''//trim(Names%label(i))//''',''isDerived'','
            if (Names%is_derived(i)) then
                write(unit,'(a)') 'true);'
            else
                write(unit,'(a)') 'false);'
            endif
        end if
    end do

    end subroutine ParamNames_WriteMatlab

    function ParamNames_ReadIniForParam(Names,Ini,Key, param) result(input)
    ! read Key[name] or Keyn where n is the parameter number
    use IniObjects
    class(TParamNames) :: Names
    class(TIniFile) :: Ini
    character(LEN=*), intent(in) :: Key
    integer, intent(in) :: param
    character(LEN=128) input

    input = ''
    if (Names%nnames>0) then
        input = Ini%Read_String(trim(key)//'['//trim(Names%name(param))//']')
    end if
    if (input=='') then
        input = Ini%Read_String(trim(Key)//trim(IntToStr(param)))
    end if

    end function ParamNames_ReadIniForParam

    function ParamNames_HasReadIniForParam(Names,Ini,Key, param) result(B)
    ! read Key[name] or Keyn where n is the parameter number
    use IniObjects
    class(TParamNames) :: Names
    class(TIniFile) :: Ini
    character(LEN=*), intent(in) :: Key
    integer, intent(in) :: param
    logical B

    B = .false.
    if (Names%nnames>0) then
        B = Ini%HasKey(trim(key)//'['//trim(Names%name(param))//']')
    end if
    if (.not. B) then
        B = Ini%HasKey(trim(Key)//trim(IntToStr(param)))
    end if

    end function ParamNames_HasReadIniForParam



    end module ParamNames