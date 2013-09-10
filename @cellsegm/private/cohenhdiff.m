%   COHENHDIFF Cohenrence enhancing diffusion
%
%   COHENHDIFF(U,DT,NITER,KAPPA)  performs coherence enhancing diffusion of the
%   image U using timestep DT and NITER iterations. KAPPA is the concuctivity
%   parameter.
%
%   COHENHDIFF(U,DT,NITER,KAPPA,'OPT',OPT) can specify analytical (OPT = 'ana') or
%   numerical (OPT = 'num') solution
%
%   COHENHDIFF(U,DT,NITER,KAPPA,'INVDIFF',INVDIFF) specifies using inverse
%   diffusion (1) or not (0)
%
%   Ex: filtim = cohenhdiff(im,0.2,100,0.0001);
%
%   Literature:
%   Algorithms for non-linear diffusion, MATLAB in a literate programming
%   style, Section 4.2, Rein van den Boomgard
%
%
%   =======================================================================================
%   Copyright (C) 2013  Erlend Hodneland
%   Email: erlend.hodneland@biomed.uib.no 
%
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU General Public License as published by
%   the Free Software Foundation, either version 3 of the License, or
%   (at your option) any later version.
% 
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU General Public License for more details.
% 
%   You should have received a copy of the GNU General Public License
%   along with this program.  If not, see <http://www.gnu.org/licenses/>.
%   =======================================================================================
%
function [u] = cohenhdiff(varargin)

u = varargin{1};
dt = varargin{2};
maxniter = varargin{3};
kappa = varargin{4};
opt = 'ana';
prm.invdiff = [];
prm.gpu = 0;
prm.h = [1 1 3];
prm.kappa = kappa;
for i = 5:2:nargin
    varhere = varargin{i};
    switch(varhere)
        case ('opt')
            opt = varargin{i+1};
        case 'invdiff'
            prm.invdiff = varargin{i+1};
        case 'prm'
            prmin = varargin{i+1};
            % merge input
            prm = mergestruct(prm,prmin);
        otherwise
            error('Wrong option to COHENHDIFF')
    end;
end;
          
if ~isempty(prm.invdiff)
    disp('Using inverse diffusion');
end;


%
% No filtering here!
%

dim = size(u);
ndim = numel(dim);

if ndim == 2
    filt1 = fspecial('gaussian',3,1);
    filt2 = fspecial('gaussian',9,5);
    if strcmp(opt,'ana')
        % 2D coherence enhancing analytical diffusion
        [u] = cohdiff2dana(u,filt1,filt2,dt,maxniter,prm);
    elseif strcmp(opt,'num')
         % 2D coherence enhancing numerical diffusion
        [u] = cohdiff2dnum(u,filt1,filt2,dt,maxniter,prm);
    else
        error('Wrong option for OPT');
    end;
elseif ndim == 3
    filt1 = gaussian([3 3 2],2);
    filt2 = gaussian([7 7 3],1);
    if strcmp(opt,'ana')
        % 3D coherence enhancing analytical diffusion 
        error('Not working analytically in 3D');
%         u = cohdiff3dana(u,filt1,filt2,dt,niter,prm);    
    elseif strcmp(opt,'num')
        % 3D coherence enhancing numerical diffusion 
        u = cohdiff3dnumcell(u,filt1,filt2,dt,maxniter,prm);    
    else
        error('Wrong option for OPT');
    end;
end;

%----------------------------------------------------------

function [u] = cohdiff2dana(u,filt1,filt2,dt,niter,prm)

h = prm.h;
kappa = prm.kappa;

% iterate
for i = 1 : niter
    
    % derivative
    [Rx Ry Rz] = derivcentr3(u,h(1),h(2),h(3));
    Rx = imfilter(Rx,filt1,'replicate');
    Ry = imfilter(Ry,filt1,'replicate');    
%     Rx = gd( u, obsscale, 1, 0 );
%     Ry = gd( u, obsscale, 0, 1 );
    
    % the elements in the structure tensor
%     s11 = gd( Rx.^2,  intscale, 0, 0 );    
%     s12 = gd( Rx.*Ry, intscale, 0, 0 );    
%     s22 = gd( Ry.^2,  intscale, 0, 0 );

    s11 = imfilter(Rx.^2,filt2,'replicate');
    s12 = imfilter(Rx.*Ry,filt2,'replicate');
    s22 = imfilter(Ry.^2,filt2,'replicate');

    % the +- thing
    alpha = sqrt( (s11-s22).^2 + 4*s12.^2 );

    % eigenvalues
    el1 = 1/2 * (s11 + s22 - alpha);
    el2 = 1/2 * (s11 + s22 + alpha);
    
    % factors in C matrix
    beta = 0.0001;
%     beta = 0.1;
    c1 = max(beta, 1-exp( -(el1-el2).^2 / kappa^2));

    if ~isempty(prm.invdiff)
        c2 = prm.invdiff;
    else
        c2 = beta;
    end;

    
    % diffusion tensor
%     eps = 1e-10;
    d11 = 1/2*(c1+c2+(c2-c1).*(s11-s22)./(alpha + eps));
    d12 = (c2-c1).*s12./(alpha + eps);
    d22 = 1/2*(c1+c2 - (c2-c1).*(s11-s22)./(alpha + eps));    
    
    % update 
    updateval = tnldstep2d(u,d11,d12,d22);
    u = u + dt*updateval;
        
end;

%----------------------------------------------------------

function [r] = tnldstep2d(L,a,b,c)

% function for computing div(D*grad(u))
% D = [a b  
%      c d]

Lpc = transim( L, 1, 0, 0 );
        Lpp = transim( L, 1, 1, 0 );
        Lcp = transim( L, 0, 1, 0 );
        Lnp = transim( L, -1, 1, 0 );
        Lnc = transim( L, -1, 0, 0 );
        Lnn = transim( L, -1, -1, 0 );
        Lcn = transim( L, 0, -1, 0 );
        Lpn = transim( L, 1, -1, 0 );
        
        anc = transim( a, -1, 0, 0 );
        apc = transim( a, +1, 0, 0 );
        bnc = transim( b, -1, 0, 0 );
        bcn = transim( b, 0, -1, 0 );
        bpc = transim( b, +1, 0, 0 );
        bcp = transim( b, 0, +1, 0 );
        ccp = transim( c, 0, +1, 0 );
        ccn = transim( c, 0, -1, 0 );
        
        r = -1/4 * (bnc+bcp) .* Lnp + ...
             1/2 * (ccp+c)   .* Lcp + ...
             1/4 * (bpc+bcp) .* Lpp + ...
             1/2 * (anc+a)   .* Lnc - ...
             1/2 * (anc+2*a+apc+ccn+2*c+ccp) .* L + ...
             1/2 * (apc+a)   .* Lpc + ...
             1/4 * (bnc+bcn) .* Lnn + ...
             1/2 * (ccn+c)   .* Lcn - ...
             1/4 * (bpc+bcn) .* Lpn;


%--------------------------------------------------------         

function [u] = cohdiff3dnumcell(u,filt1,filt2,dt,niter,prm)

h = prm.h;
kappa = prm.kappa;

% NB must have double precision, otherwise you can get NaN's due to bad precision???!!!
if prm.gpu
    u = gdouble(u);
    filt1 = gdouble(filt1);
    filt2 = gdouble(filt2);
    h = gdouble(h);
end;

prm.gpu
% dim = size(u);
% iterate
for i = 1 : niter
            
    
    % derivatives    
    [Rx Ry Rz] = derivcentr3(u,h(1),h(2),h(3));

    % smooth the derivatives
     if prm.gpu
         Rx = imfiltergpu(Rx,filt1);
         Ry = imfiltergpu(Ry,filt1);
         Rz = imfiltergpu(Rz,filt1);   
     else
        Rx = imfilter(Rx,filt1,'replicate');
        Ry = imfilter(Ry,filt1,'replicate');    
        Rz = imfilter(Rz,filt1,'replicate');        
      end;
    
    % construct the structure tensor
    s{1,1} = Rx.^2;
    s{2,1} = Rx.*Ry;
    s{3,1} = Rx.*Rz;    
    s{2,2} = Ry.^2;
    s{3,2} = Ry.*Rz;
    s{3,3} = Rz.^2;
   
    % smooth the structure tensor
    for j = 1 : 3
        for k = 1 : j
            if prm.gpu                
                s{j,k} = imfiltergpu(s{j,k},filt2);
            else
                s{j,k} = imfilter(s{j,k},filt2,'replicate');
            end;
        end;
    end;    
    s{1,2} = s{2,1};
    s{1,3} = s{3,1};
    s{2,3} = s{3,2};

    % find eigenvalues and eigenvectors by QR factorization
    [R D] = eigcell(s);
    r11 = R{1,1};r12 = R{1,2};r13 = R{1,3};
    r21 = R{2,1};r22 = R{2,2};r23 = R{2,3};
    r31 = R{3,1};r32 = R{3,2};r33 = R{3,3};
    mu1 = D{1,1};mu2 = D{2,2};mu3 = D{3,3};    
               
    
    lambdac = 0.02;       
    lambda1= kappa + (1.0- kappa)*exp(-0.6931*lambdac^2./(mu2./(kappa+mu1)).^4);
    lambda1((mu2<1e-15)&(mu2>-1e-15))=0;
    lambda1((mu1<1e-15)&(mu1>-1e-15))=0;
    lambda2= lambda1;
    lambda3 = kappa;

          
    % REMARK: You MUST use R*C*R' here, NOT R'*C*R !!! This is the
    % eigenvector decomposition
    % Computed in Matlab
    % R*C*R' = 
    % [ c1*r11*(r11) + c2*r12*(r12) + c3*r13*(r13), c1*r11*(r21) + c2*r12*(r22) + c3*r13*(r23), c1*r11*(r31) + c2*r12*(r32) + c3*r13*(r33)]
    % [ c1*r21*(r11) + c2*r22*(r12) + c3*r23*(r13), c1*r21*(r21) + c2*r22*(r22) + c3*r23*(r23), c1*r21*(r31) + c2*r22*(r32) + c3*r23*(r33)]
    % [ c1*r31*(r11) + c2*r32*(r12) + c3*r33*(r13), c1*r31*(r21) + c2*r32*(r22) + c3*r33*(r23), c1*r31*(r31) + c2*r32*(r32) + c3*r33*(r33)]
        
    % For curiosity:
    % R'*C*R
    %  
    % [ c1*r11*(r11) + c2*r21*(r21) + c3*r31*(r31), c1*r12*(r11) + c2*r22*(r21) + c3*r32*(r31), c1*r13*(r11) + c2*r23*(r21) + c3*r33*(r31)]
    % [ c1*r11*(r12) + c2*r21*(r22) + c3*r31*(r32), c1*r12*(r12) + c2*r22*(r22) + c3*r32*(r32), c1*r13*(r12) + c2*r23*(r22) + c3*r33*(r32)]
    % [ c1*r11*(r13) + c2*r21*(r23) + c3*r31*(r33), c1*r12*(r13) + c2*r22*(r23) + c3*r32*(r33), c1*r13*(r13) + c2*r23*(r23) + c3*r33*(r33)]


    % Construct the diffusion tensor
    D{1,1} = lambda1.*r11.^2 + lambda2.*r12.^2 + lambda3.*r13.^2;
    D{2,2} = lambda1.*r21.^2 + lambda2.*r22.^2 + lambda3.*r23.^2;
    D{3,3} = lambda1.*r31.^2 + lambda2.*r32.^2 + lambda3.*r33.^2;

    D{2,1} = lambda1.*r11.*r21 + lambda2.*r12.*r22 + lambda3.*r13.*r23;
    D{3,1} = lambda1.*r11.*r31 + lambda2.*r12.*r32 + lambda3.*r13.*r33;
    D{3,2} = lambda1.*r21.*r31 + lambda2.*r22.*r32 + lambda3.*r23.*r33;              


    % update equation    
    update = tnldstep3d(u,D,prm); 
    u = u + dt*update;     
    
end;

if prm.gpu 
    u = double(u);
end;

%-----------------------------------------------------------   

function [u] = cohdiff2dnum(u,filt1,filt2,dt,niter,prm)

kappa = prm.kappa;
h = prm.h;

dim = size(u);
% iterate
for i = 1 : niter
    
    % derivative
    [Rx Ry Rz] = derivcentr3(u,h(1),h(2),h(3));
    Rx = imfilter(Rx,filt1,'replicate');
    Ry = imfilter(Ry,filt1,'replicate');    

    s11 = imfilter(Rx.^2,filt2,'replicate');
    s21 = imfilter(Rx.*Ry,filt2,'replicate');
    s22 = imfilter(Ry.^2,filt2,'replicate');
    
    r11 = zeros(dim);
    r21 = zeros(dim);
    r22 = zeros(dim);
    e1 = zeros(dim);
    e2 = zeros(dim);
    for j = 1 : dim(1)
        for k = 1 : dim(2)
            mhere = [s11(j,k) s21(j,k);
                     s21(j,k) s22(j,k)];   
            [v d] = eig(mhere);
                
            r11(j,k) = v(1,1);
            r21(j,k) = v(2,1);
            r22(j,k) = v(2,2);
            
            e1(j,k) = d(1,1);
            e2(j,k) = d(2,2);            
        end;
    end;
    

    % factors in C matrix   
    beta = 0.01;
    c1 = max(beta, 1-exp( -(e1-e2).^2 / kappa^2));
    if ~isempty(prm.invdiff)
        c2 = prm.invdiff;
    else
        c2 = beta;
    end;

    % D matrix
    d11 = r11.^2.*c1+r21.^2.*c2;
    d12 = r11.*c1.*r21+r21.*c2.*r22;
    d22 = r21.^2.*c1+r22.^2.*c2;

    % update 
    update = tnldstep2d(u,d11,d12,d22);
    u = u + dt* update;
    
    msg = ['Number of iterations: ' int2str(i)];
    disp(msg);
        
end;


%-----------------------------------------------------

function [r] = tnldstep3d(L,D,prm)
               
d11 = D{1,1};
d21 = D{2,1};
d22 = D{2,2};
d31 = D{3,1};
d32 = D{3,2};
d33 = D{3,3};

h(1) = prm.h(1);
h(2) = prm.h(2);
h(3) = prm.h(3);


% Function for computing div(D*grad(u))
% Using averaging of dxdx, dydy, dzdz along forward and backward differences
% For mixed terms we use central differences, as in Boomgaard, Algorithms
% for non-linear diffusion

r =   (1/(2*h(1)^2))*((d11 + transim(d11,1,0,0)).*(transim(L,1,0,0) - L) - (transim(d11,-1,0,0) + d11) .* (L - transim(L,-1,0,0))) ...
    + (1/(2*h(2)^2))*((d22 + transim(d22,0,1,0)).*(transim(L,0,1,0) - L) - (transim(d22,0,-1,0) + d22) .* (L - transim(L,0,-1,0))) ...
    + (1/(2*h(3)^2))*((d33 + transim(d33,0,0,1)).*(transim(L,0,0,1) - L) - (transim(d33,0,0,-1) + d33) .* (L - transim(L,0,0,-1))) ... 
    ...
    + (1/(4*h(1)*h(2)))*(transim(d21,1,0,0).*(transim(L,1,1,0) - transim(L,1,-1,0)) - transim(d21,-1,0,0).*(transim(L,-1,1,0) - transim(L,-1,-1,0))) ...
    + (1/(4*h(1)*h(3)))*(transim(d31,1,0,0).*(transim(L,1,0,1) - transim(L,1,0,-1)) - transim(d31,-1,0,0).*(transim(L,-1,0,1) - transim(L,-1,0,-1))) ...;
    ...
    + (1/(4*h(2)*h(1)))*(transim(d21,0,1,0).*(transim(L,1,1,0) - transim(L,-1,1,0)) - transim(d21,0,-1,0).*(transim(L,1,-1,0) - transim(L,-1,-1,0))) ...
    + (1/(4*h(2)*h(3)))*(transim(d32,0,1,0).*(transim(L,1,0,1) - transim(L,1,0,-1)) - transim(d32,0,-1,0).*(transim(L,-1,0,1) - transim(L,-1,0,-1))) ...
    ...
    + (1/(4*h(3)*h(1)))*(transim(d31,0,0,1).*(transim(L,1,0,1) - transim(L,-1,0,1)) - transim(d31,0,0,-1).*(transim(L,1,0,-1) - transim(L,-1,0,-1))) ...
    + (1/(4*h(3)*h(2)))*(transim(d32,0,0,1).*(transim(L,0,1,1) - transim(L,0,-1,1)) - transim(d32,0,0,-1).*(transim(L,0,1,-1) - transim(L,0,-1,-1)));


% 
% % original scheme
% p1 = d11.*(transim(L,1,0,0)-L)/h(1);
% p2 = d12.*(transim(L,0,1,0)-transim(L,0,-1,0))/(2*h(2));
% p3 = d13.*(transim(L,0,0,1)-transim(L,0,0,-1))/(2*h(3));
% 
% p4 = d21.*(transim(L,1,0,0)-transim(L,-1,0,0))/(2*h(1));
% p5 = d22.*(transim(L,0,1,0)-L)/h(2);
% p6 = d23.*(transim(L,0,0,1)-transim(L,0,0,-1))/(2*h(3));
% 
% p7 = d31.*(transim(L,1,0,0)-transim(L,-1,0,0))/(2*h(1));
% p8 = d32.*(transim(L,0,1,0)-transim(L,0,-1,0))/(2*h(2));
% p9 = d33.*(transim(L,0,0,1)-L)/h(3);
% 
% r = ...
%     (p1-transim(p1,-1,0,0))/h(1) + ...
%     (transim(p2,1,0,0)-transim(p2,-1,0,0))/(2*h(1)) + ...
%     (transim(p3,1,0,0)-transim(p3,-1,0,0))/(2*h(1)) + ...
%     ...
%     (transim(p4,0,1,0)-transim(p4,0,-1,0))/(2*h(2)) + ...
%     (p5-transim(p5,0,-1,0))/h(2) + ...
%     (transim(p6,0,1,0)-transim(p6,0,-1,0))/(2*h(2)) + ...    
%     ...
%     (transim(p7,0,0,1)-transim(p7,0,0,-1))/(2*h(3)) + ...
%     (transim(p8,0,0,1)-transim(p8,0,0,-1))/(2*h(3)) + ...
%     (p9-transim(p9,0,0,-1))/h(3);

