c       
c       
c       Generalized helmholtz FMM in R^3: evaluate all pairwise particle
c       interactions (ignoring self-interaction) 
c       and interactions with targets 
c
c       We use exp(ikr)/r for the Green's function., without
c       the 1/(4\pi ) scaling.
c
c   
c-----------------------------------------------------------
        subroutine hfmm3d_ndiv(nd,eps,zk,nsource,source,ifcharge,
     $    charge,ifdipole,dipvec,iper,ifpgh,pot,grad,hess,ntarg,
     $    targ,ifpghtarg,pottarg,gradtarg,hesstarg,ndiv,idivflag,
     $    ifnear,timeinfo,ier)
c-----------------------------------------------------------------------
c   INPUT PARAMETERS:
c
c   nd:    in: integer
c             number of densities
c   
c   eps:   in: double precision
c             requested precision
c
c   zk:    in: double complex
c               helmholtz parameter                
c
c   nsource in: integer  
c                number of sources
c
c   source  in: double precision (3,nsource)
c                source(k,j) is the kth component of the jth
c                source locations
c
c   ifcharge  in: integer  
c             charge computation flag
c              ifcharge = 1   =>  include charge contribution
c                                     otherwise do not
c 
c   charge    in: double complex (nd,nsource) 
c              charge strengths
c
c   ifdipole   in: integer
c              dipole computation flag
c              ifdipole = 1   =>  include dipole contribution
c                                     otherwise do not
c
c   dipvec   in: double precision (nd,3,nsource) 
c              dipole orientation vectors
c   iper    in: integer
c             flag for periodic implmentations. Currently unused
c   ifpgh   in: integer
c              flag for evaluating potential/gradient at the sources
c              ifpgh = 1, only potential is evaluated
c              ifpgh = 2, potential and gradients are evaluated
c
c
c   ntarg  in: integer  
c                 number of targs 
c
c   targ  in: double precision (3,ntarg)
c               targ(k,j) is the kth component of the jth
c               targ location
c
c   ifpghtarg   in: integer
c              flag for evaluating potential/gradient at the targs
c              ifpghtarg = 1, only potential is evaluated
c              ifpghtarg = 2, potential and gradient are evaluated
c
c
c     OUTPUT parameters:
c
c   pot:    out: double complex(nd,nsource) 
c               potential at the source locations
c
c   grad:   out: double complex(nd,3,nsource)
c               gradient at the source locations
c
c   hess    out: double complex(nd,6,nsource)
c               hessian at the source locations
c
c   pottarg:    out: double complex(nd,ntarg) 
c               potential at the targ locations
c
c   gradtarg:   out: double complex(nd,3,ntarg)
c               gradient at the targ locations
c
c   hesstarg    out: double complex(nd,6,ntarg)
c                hessian at the target locations
c
c   ier         out: integer
c                error flag
c                ier = 0, for successful execution
c                ier = 4, if failed to allocate workspace
c                      for multipole and local expansions
c                ier = 8, if failed to allocate workspace
c                      for plane wave expansions
c     
     
c------------------------------------------------------------------

      implicit none

      integer nd
      integer iper
      integer ier

      double complex zk
      double precision eps

      integer ifcharge,ifdipole
      integer ifpgh,ifpghtarg

      integer nsource,ntarg

      double precision source(3,nsource),targ(3,ntarg)
      double complex charge(nd,nsource)

      double complex dipvec(nd,3,nsource)

      double complex pot(nd,nsource),grad(nd,3,nsource),
     1     pottarg(nd,3,ntarg),
     1     gradtarg(nd,3,ntarg),hess(nd,6,*),hesstarg(nd,6,*)
      double precision timeinfo(6)

c       Tree variables
      integer mhung,idivflag,ndiv,isep,nboxes,nbmax,nlevels
      integer nlmax
      integer mnbors
      integer ifunif,nlmin
      integer *8 ipointer(8),ltree
      integer, allocatable :: itree(:)
      integer, allocatable :: isrcse(:,:),itargse(:,:),isrc(:)
      integer, allocatable :: itarg(:)
      integer, allocatable :: iexpcse(:,:)
      integer iexpc
      double precision, allocatable :: treecenters(:,:),boxsize(:)
      double precision b0,b0inv,b0inv2,b0inv3
      double complex zkfmm

c
cc      temporary sorted arrays
c
      double precision, allocatable :: sourcesort(:,:),targsort(:,:)
      double complex, allocatable :: chargesort(:,:)
      double complex, allocatable :: dipvecsort(:,:,:)

      double complex, allocatable :: potsort(:,:),gradsort(:,:,:),
     1       hesssort(:,:,:)
      double complex, allocatable :: pottargsort(:,:),
     1    gradtargsort(:,:,:),hesstargsort(:,:,:)

c
cc       temporary fmm arrays
c
      double precision epsfmm
      integer, allocatable :: nterms(:)
      integer *8, allocatable :: iaddr(:,:)
      double precision, allocatable :: scales(:)
      double precision, allocatable :: rmlexp(:)

      integer lmptemp,nmax
      integer *8 lmptot
      double precision, allocatable :: mptemp(:),mptemp2(:)

c
cc       temporary variables not used in particle code
c
      double precision expc(3),scjsort(1),radexp
      double complex texpssort(100)
      double precision expcsort(3),radssort(1)
      integer ntj,nexpc,nadd,ifnear

c
cc        other temporary variables
c
      integer i,iert,ifprint,ilev,idim
      double precision time1,time2,omp_get_wtime,second

       
c
c
c     ifprint is an internal information printing flag. 
c     Suppressed if ifprint=0.
c     Prints timing breakdown and other things if ifprint=1.
c      
      ifprint=0
      nexpc = 0
      nadd = 0
      ntj = 0
c
cc      set tree flags
c 
       nlmax = 51
       nlevels = 0
       nboxes = 0
       ltree = 0
       nlmin = 0
       ifunif = 0
       iper = 0

c
cc     memory management code for contructing level restricted tree
      call pts_tree_mem(source,nsource,targ,ntarg,idivflag,ndiv,nlmin,
     1  nlmax,iper,ifunif,nlevels,nboxes,ltree)
      

        if(ifprint.ge.1) print *, ltree/1.0d9

        allocate(itree(ltree))
        allocate(boxsize(0:nlevels))
        allocate(treecenters(3,nboxes))

c       Call tree code
      call pts_tree_build(source,nsource,targ,ntarg,idivflag,ndiv,
     1  nlmin,nlmax,iper,ifunif,nlevels,nboxes,ltree,itree,ipointer,
     2  treecenters,boxsize)
      

      allocate(isrcse(2,nboxes),itargse(2,nboxes),iexpcse(2,nboxes))
      allocate(isrc(nsource),itarg(ntarg))

      call pts_tree_sort(nsource,source,itree,ltree,nboxes,nlevels,
     1   ipointer,treecenters,isrc,isrcse)

      call pts_tree_sort(ntarg,targ,itree,ltree,nboxes,nlevels,
     1   ipointer,treecenters,itarg,itargse)
      
      call pts_tree_sort(nexpc,expc,itree,ltree,nboxes,nlevels,
     1   ipointer,treecenters,iexpc,iexpcse)

c
c   End of tree build
c


c
c  Set rescaling parameters
c
      b0 = boxsize(0)
      b0inv = 1.0d0/b0
      b0inv2 = b0inv**2


c     Allocate sorted source and target arrays      

      allocate(sourcesort(3,nsource))
      allocate(targsort(3,ntarg))
      if(ifcharge.eq.1) allocate(chargesort(nd,nsource))
      if(ifdipole.eq.1) then
         allocate(dipvecsort(nd,3,nsource))
      endif

      if(ifpgh.eq.1) then 
        allocate(potsort(nd,nsource),gradsort(nd,3,1),hesssort(nd,6,1))
      else if(ifpgh.eq.2) then
        allocate(potsort(nd,nsource),gradsort(nd,3,nsource),
     1       hesssort(nd,6,1))
      else if(ifpgh.eq.3) then
        allocate(potsort(nd,nsource),gradsort(nd,3,nsource),
     1       hesssort(nd,6,nsource))
      else
        allocate(potsort(nd,1),gradsort(nd,3,1),hesssort(nd,6,1))
      endif

      if(ifpghtarg.eq.1) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,1),
     1      hesstargsort(nd,6,1))
      else if(ifpghtarg.eq.2) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,ntarg),
     1        hesstargsort(nd,6,1))
      else if(ifpghtarg.eq.3) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,ntarg),
     1        hesstargsort(nd,6,ntarg))
      else
        allocate(pottargsort(nd,1),gradtargsort(nd,3,1),
     1     hesstargsort(nd,6,1))
      endif

      allocate(nterms(0:nlevels)) 
c
cc      initialize potential and gradient at source
c       locations
c
      if(ifpgh.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpgh.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)

        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
            gradsort(idim,1,i) = 0
            gradsort(idim,2,i) = 0
            gradsort(idim,3,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif


      if(ifpgh.eq.3) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
            gradsort(idim,1,i) = 0
            gradsort(idim,2,i) = 0
            gradsort(idim,3,i) = 0
            hesssort(idim,1,i) = 0
            hesssort(idim,2,i) = 0
            hesssort(idim,3,i) = 0
            hesssort(idim,4,i) = 0
            hesssort(idim,5,i) = 0
            hesssort(idim,6,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif



c
cc       initialize potential and gradient  at targ
c        locations
c
      if(ifpghtarg.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpghtarg.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
            gradtargsort(idim,1,i) = 0
            gradtargsort(idim,2,i) = 0
            gradtargsort(idim,3,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpghtarg.eq.3) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
            gradtargsort(idim,1,i) = 0
            gradtargsort(idim,2,i) = 0
            gradtargsort(idim,3,i) = 0
            hesstargsort(idim,1,i) = 0
            hesstargsort(idim,2,i) = 0
            hesstargsort(idim,3,i) = 0
            hesstargsort(idim,4,i) = 0
            hesstargsort(idim,5,i) = 0
            hesstargsort(idim,6,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

c
cc       reorder sources
c
      call dreorderf(3,nsource,source,sourcesort,isrc)
      call drescale(3*nsource,sourcesort,b0inv)
      if(ifcharge.eq.1) then
        call dreorderf(2*nd,nsource,charge,chargesort,isrc)
        call drescale(2*nd*nsource,chargesort,b0inv)
      endif

      if(ifdipole.eq.1) then
         call dreorderf(6*nd,nsource,dipvec,dipvecsort,isrc)
         call drescale(6*nd*nsource,dipvecsort,b0inv2)
      endif

c
cc      reorder targs
c
      call dreorderf(3,ntarg,targ,targsort,itarg)
      call drescale(3*ntarg,targsort,b0inv)
c
c  update tree centers and boxsize
c
      call drescale(3*nboxes,treecenters,b0inv)
      call drescale(nlevels+1,boxsize,b0inv)

      zkfmm = zk*b0

c
c     scaling factor for multipole and local expansions at all levels
c
      allocate(scales(0:nlevels))
      do ilev = 0,nlevels
       scales(ilev) = boxsize(ilev)*abs(zkfmm)
       if(scales(ilev).gt.1) scales(ilev) = 1
      enddo


c     Compute length of expansions at each level      
      nmax = 0
      if(ifprint.ge.1) call prin2('boxsize=*',boxsize,nlevels+1)
      if(ifprint.ge.1) call prin2('zkfmm=*',zkfmm,2)
      do i=0,nlevels
         call h3dterms(boxsize(i),zkfmm,eps,nterms(i))
         if(nterms(i).gt.nmax) nmax = nterms(i)
      enddo
      if(ifprint.ge.1) call prinf('nlevels=*',nlevels,1)
      if(ifprint.ge.1) call prinf('nterms=*',nterms,nlevels+1)
c       
c     Multipole and local expansions will be held in workspace
c     in locations pointed to by array iaddr(2,nboxes).
c
c     iiaddr is pointer to iaddr array, itself contained in workspace.
c     imptemp is pointer for single expansion (dimensioned by nmax)
c
c       ... allocate iaddr and temporary arrays
c

      allocate(iaddr(2,nboxes))
      lmptemp = (nmax+1)*(2*nmax+1)*2*nd
      allocate(mptemp(lmptemp),mptemp2(lmptemp))

c
c     allocate memory need by multipole, local expansions at all
c     levels
c     irmlexp is pointer for workspace need by various fmm routines,
c
      call mpalloc(nd,itree(ipointer(1)),iaddr,nlevels,lmptot,nterms)
      if(ifprint.ge. 1) print *, "lmptot =",lmptot/1.0d9

      allocate(rmlexp(lmptot),stat=iert)
      ier = 0
      if(iert.ne.0) then
         print *, "Cannot allocate mpole expansion workspace"
         print *, "lmptot=", lmptot
         ier = 4
         return
      endif


c     Memory allocation is complete.
c     Call main fmm routine
c
      call cpu_time(time1)
C$    time1=omp_get_wtime()
      call hfmm3dmain(nd,eps,zkfmm,
     $   nsource,sourcesort,
     $   ifcharge,chargesort,
     $   ifdipole,dipvecsort,
     $   ntarg,targsort,nexpc,expcsort,radssort,
     $   iaddr,rmlexp,lmptot,mptemp,mptemp2,lmptemp,
     $   itree,ltree,ipointer,ndiv,nlevels,
     $   nboxes,iper,boxsize,treecenters,isrcse,itargse,iexpcse,
     $   scales,itree(ipointer(1)),nterms,
     $   ifpgh,potsort,gradsort,hesssort,ifpghtarg,pottargsort,
     $   gradtargsort,hesstargsort,ntj,texpssort,scjsort,ifnear,
     $   timeinfo,ier)

      call cpu_time(time2)
C$    time2=omp_get_wtime()
      if( ifprint .eq. 1 ) call prin2('time in fmm main=*',
     1   time2-time1,1)


      if(ifpgh.ge.1) then
        call dreorderi(2*nd,nsource,potsort,pot,isrc)
      endif
      if(ifpgh.ge.2) then 
        call dreorderi(6*nd,nsource,gradsort,grad,isrc)
        call drescale(6*nd*nsource,grad,b0inv)
      endif

      if(ifpgh.ge.3) then 
        call dreorderi(12*nd,nsource,hesssort,hess,isrc)
        call drescale(12*nd*nsource,hess,b0inv2)
      endif


      if(ifpghtarg.ge.1) then
        call dreorderi(2*nd,ntarg,pottargsort,pottarg,itarg)
      endif

      if(ifpghtarg.ge.2) then
        call dreorderi(6*nd,ntarg,gradtargsort,gradtarg,itarg)
        call drescale(6*nd*ntarg,gradtarg,b0inv)
      endif

      if(ifpghtarg.ge.3) then
        call dreorderi(12*nd,ntarg,hesstargsort,hesstarg,itarg)
        call drescale(12*nd*ntarg,hesstarg,b0inv2)
      endif


      return
      end
