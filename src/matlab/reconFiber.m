clear all; close all;

%Load quadrature
load qsph1-37-492DP.dat; 
quadPnts = qsph1_37_492DP(:,1:3);
N = 18;        %maximum degree of subspace
nQpnts = 492;  %number of points in quadrature

%Sample signal on lower degree quadrature 
load qsph1-16-132DP.dat; 
samplePnts  = qsph1_16_132DP(:,1:3);
nSamplePnts = 132;                       

%Create reproducing-kernel (sparse representation) matrix
nA = matrix(quadPnts,samplePnts,nQpnts,nSamplePnts,N);

%Create signal
sprintf('Creating signal...')
nFibers = 2;                      %number of Gaussian components (max n=3)
b       = 3000;                   %s/mm^2
rAngle = -pi/2;
signal = zeros(nSamplePnts,1)';
for i=1:nSamplePnts                             
  signal(i) = randSig(samplePnts(i,1:3)',b,nFibers,rAngle); 
end


nRealizations = 1;
for kk=1:nRealizations
    
    %Make Rician noise
    sigma  = 0.0;                          %standard deviation            
    noiseR = sigma * randn(size(signal));
    noiseI = sigma * randn(size(signal));
    noise  = noiseR + i*noiseI;

    SNR(kk) = 10 * log10(norm(signal,2)/norm(noise,2));
    sprintf('Signal to noise ratio: %0.5g',SNR(kk));

    %Add noise to signal
    rSig = signal + noise;
    rSig = abs(rSig);      %only real part is used in MRI

    %Choose regularization parameter
    lambda_max = 2*norm(transpose(nA)*rSig',inf); %lambda > lambda_max -> zero solution
    lambda = 0.1275*lambda_max;

   
    sprintf('Solving L1 penalized system...')
    %Solve L_1 minimization problem with CVX
    cvx_begin
      variable ndCoefsl1(nQpnts);
      cvx_precision('low');
      minimize( norm( nA * ndCoefsl1 - rSig',2) + lambda*norm(ndCoefsl1,1) );
      subject to 
        0.0 <= ndCoefsl1;
    cvx_end

    %Cutoff those coefficients that are less than cutoff
    cutoff = mean(ndCoefsl1) + 2.5*std(ndCoefsl1);
    mask = ndCoefsl1 > cutoff;
    ndCoefsl1_trim = ndCoefsl1 .* mask;
   
    %Sort coefficients and keep track of indices
    [sortedCoefs, sortedIndex] = sort(ndCoefsl1_trim,'descend');
    nSig = sum(ndCoefsl1_trim > 0);              %number of significant coefficients
    sprintf('Compression: %0.5g',nSig/nQpnts);
    
    %Used for taking only some of the points---now using the whole sphere
    %Let -1.5 -> 0 and get only the hemisphere with x>0
    indexPos = sortedIndex(find(quadPnts(sortedIndex(1:nSig),1) >= -1.5)); 
    points   = quadPnts(indexPos,1:3);

    
    %Sort by x-coordinate in descending order
    points = sortrows(points,[-1]);

    clear ZZ h t p p1 mp1 mw1 p2 mp2 mw2 p3 mp3 mw3
    
    %Start clustering algorithm using cosine distance 
    nClusters = 4;
    ZZ = linkage(points,'single','cosine');
    [h, t, p] = dendrogram(ZZ,nClusters);

    %Check if there's more than one point in cluster; if so, take mean.
    p1 = points(t==1,1:3);
    if(sum(t==1)==1)       
      mp1 = p1; mp1 = mp1./norm(mp1);
      mw1 = ndCoefsl1(indexPos(t==1));  
    elseif(sum(t==1)>1) 
      mp1 = mean(p1); mp1 = mp1./norm(mp1);
      mw1 = mean(ndCoefsl1(indexPos(t==1)));
    end

    p2 = points(t==2,1:3);
    if(sum(t==2)==1)      
      mp2 = p2; mp2 = mp2./norm(mp2);
      mw2 = ndCoefsl1(indexPos(t==2));    
    elseif(sum(t==2)>1) 
      mp2 = mean(p2); mp2 = mp2./norm(mp2);
      mw2 = mean(ndCoefsl1(indexPos(t==2)));            
    end

    p3 = points(t==3,1:3);
    if(sum(t==3)==1)           
      mp3 = p3; mp3 = mp3./norm(mp3);
      mw3 = ndCoefsl1(indexPos(t==3));
    elseif(sum(t==3)>1) 
      mp3 = mean(p3); mp3 = mp3./norm(mp3);
      mw3 = mean(ndCoefsl1(indexPos(t==3)));    
    end

    p4 = points(t==4,1:3);
    if(sum(t==4)==1)                
      mp4 = p4; mp4 = mp4./norm(mp4);
      mw4 = ndCoefsl1(indexPos(t==4));   
    elseif(sum(t==4)>1) 
      mp4 = mean(p4); mp4 = mp4./norm(mp4);
      mw4 = mean(ndCoefsl1(indexPos(t==4)));            
    end

    %Centroids of the four clusters
    mpoints = [mp1; mp2; mp3; mp4];
    
    %Sorted by decreasing x values
    mpoints = sortrows(mpoints,[-1]);

    %Find angle between fiber 1 and pos-x axis -- Should be 0
    a1(kk) = acos(dot(mpoints(1,1:3),[1 0 0]))*180/pi;
    
    if(mpoints(2,2)>0)
      a2(kk) = acos(dot(mpoints(2,1:3),[cos(-rAngle)  sin(-rAngle) 0]))*180/pi;
    else
      a2(kk) = acos(dot(mpoints(2,1:3),[cos(-rAngle) -sin(-rAngle) 0]))*180/pi;
    end
    
    %Find anlge between fibers
    ab(kk) = acos(dot(mpoints(1,1:3),mpoints(2,1:3)))*180/pi;
    
    %ratio of mean coefficients --- indication of volume fraction?
    r(kk) = mw1/mw2;

end


%Get statistics 
angle1  = mean(a1); std1     = sqrt(var(a1)); 
angle2  = mean(a2); std2     = sqrt(var(a2));
anglebw = mean(ab); stdbw    = sqrt(var(ab)); 
ratio   = mean(r);  stdratio = sqrt(var(r)); 

