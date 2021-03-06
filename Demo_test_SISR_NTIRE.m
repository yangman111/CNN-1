%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Made by 'Woong.Bae' (iorism@kaist.ac.kr) at 2017.4.16
% CVPRW 2017 Paper : Beyond Deep Residual Learning for Image Restoration: Persistent Homology-Guided Manifold Simplification


% Copyright <2017> <Woong.Bae(iorism@kaist.ac.kr)>
% 
% Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
% 
% 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

% 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
% 
% 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
% THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
% IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
% OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
% EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%

clear;
close all;

g=gpuDevice(1);
reset(g); %GPU reset

%% Path setting
addpath('utilities');
addpath('matconvnet-1.0-beta20\matlab');  %%% input matconvnet path
addpath('matconvnet-1.0-beta20\matlab\simplenn');  %%% input matconvnet path
run('vl_setupnn.m');
% run(fullfile('vl_simplenn.m'));

%% mode setting
nImgMakingMode = 0; % 0 : make LR by imresize // 1 : load LR,HR files // 2 : make HR from LR file and save
% 0 : Input High resolution image. then generate Low resolution image using bicubic down sampling
% 1 : Input High and Low resolution image. It don't use down sampling method
% 2 : Input Low resolution image. then select whether compare with High resolution image or not

%% testing setting
imageSets   = {'Set14'};  %%% select the datasets for each tasks
% Set14 , Urban100 , valid_x2_bicubic , valid_x2_unknown , test_x2_bicubic , test_x2_unknown

scale   = 2;    % SISR scale of downsampling
NetworkMode = 1;  %1 : RGB bicubic // 2 : RGB unknown

load(fullfile('model_NTIRE','\Bicubic_x2net.mat')); %%% learned dataset for NTIRE
% Bicubic_x2net Bicubic_x234net Unknow_x2net Unknow_x3net Unknow_x4net

bFileSave = 0;  % whether to save the resulting image or not
bPatchMode = 1; % For large image

setTest     = {imageSets([1])};
folderTest  = 'testsets';
folderlable  = 'lablesets';
folderResult = 'results';

%% start SISR - File load and create folder
elapsed_time_Total = 0;           

if ~exist(folderResult,'file')
    mkdir(folderResult);
end

st = dwtmode('sym'); %sym %ppd
net.layers(end) = [] ;
net = vl_simplenn_move(net, 'gpu') ;   

setTestCur = cell2mat(setTest{1}(1));
disp('--------------------------------------------');
disp(['----',setTestCur,'-----Super-Resolution-----']);
disp('--------------------------------------------');
folderTestCur = fullfile(folderTest,setTestCur);
folderLableCur = fullfile(folderlable,setTestCur);
ext                 =  {'*.jpg','*.png','*.bmp'};
filepaths_Low           =  [];                      
filepaths_Lable           =  [];
for i = 1 : length(ext)
    filepaths_Low = cat(1,filepaths_Low,dir(fullfile(folderTestCur, ext{i})));
    filepaths_Lable = cat(1,filepaths_Lable,dir(fullfile(folderLableCur, ext{i})));            
end

folderResultCur = fullfile(folderResult, ['SR','_',setTestCur,'_x',num2str(scale)]);
if ~exist(folderResultCur,'file')
    mkdir(folderResultCur);
end

PSNRs_1 = zeros(1,length(filepaths_Low));
SSIMs_1 = zeros(1,length(filepaths_Low)); 
for i = 1 : length(filepaths_Low)
    HR  = imread(fullfile(folderTestCur,filepaths_Low(i).name));
    [~,imageName,ext] = fileparts(filepaths_Low(i).name);              
   label_RGB = HR;
   chanel = size(HR,3);

   if nImgMakingMode == 0              
     im = HR;                                        
     imhigh  = modcrop(im, crop); 
     imhigh = single(imhigh);
     imlow = imresize(imhigh, 1/scale, 'bicubic');             

   elseif nImgMakingMode == 1             
     imlow = imread(fullfile(folderTestCur,filepaths_Low(i).name));       %filepaths_Low                  
     imlow = single(imlow);                              
   else
     bFileSave = 1;            
     imlow = single(HR); 
   end          

   if NetworkMode <= 1
       imlow = imresize(imlow, scale, 'bicubic');
   end
   if chanel == 3               
       imlowy = imlow;
       if nImgMakingMode == 2
           label_RGB = imlow; %unknown
       end               
   else
        imlowy = imlow;                
   end
   
      %% Restoration
        tic;                
        if NetworkMode == 1  % Bicubic down-sampling on RGB
            LR_input = imlowy;
            Ysize = ceil(size(LR_input,1)/2); % +3;
            Xsize = ceil(size(LR_input,2)/2); % +3;
            input = zeros(Ysize,Xsize,12,'single');
            [input(:,:,1), input(:,:,2), input(:,:,3), input(:,:,4)] = dwt2(LR_input(:,:,1), 'haar'); %db4 %coif2 sym4 haar       
            [input(:,:,5), input(:,:,6), input(:,:,7), input(:,:,8)] = dwt2(LR_input(:,:,2), 'haar');
            [input(:,:,9), input(:,:,10), input(:,:,11), input(:,:,12)] = dwt2(LR_input(:,:,3), 'haar');

            if bPatchMode == 1
                ImageSize = Ysize*Xsize;               
                patchmode = 0;
                if ImageSize > 500259  && ImageSize < 750000
                    patchmode = 1;
                elseif ImageSize >= 750000
                    patchmode = 2;
                end
                output_T = runPatchWNet(net, input, 1, 20, patchmode);   %20                      
            else
                input = gpuArray(input);
                res    = vl_simplenn(net,input,[],[],1,'conserveMemory',true,'mode','test');                     
                output = input - res(end).x;
                output_T = gather(output);
            end
            output = zeros(size(label_RGB,1), size(label_RGB,2), 3, 'single'); %4
            output(:,:,1) = idwt2(output_T(:,:,1),output_T(:,:,2),output_T(:,:,3),output_T(:,:,4),'haar');
            output(:,:,2) = idwt2(output_T(:,:,5),output_T(:,:,6),output_T(:,:,7),output_T(:,:,8),'haar');
            output(:,:,3) = idwt2(output_T(:,:,9),output_T(:,:,10),output_T(:,:,11),output_T(:,:,12),'haar');

            if size(LR_input,1) < size(output,1)
                output = output(1:end-1,:);
            end
            if size(LR_input,2) < size(output,2)
                output = output(:,1:end-1);
            end                    
            
            if chanel == 3
                %%% output_RGB (uint8)
%                 if NetworkMode == 0
%                     output = cat(3,output,imlowcb,imlowcr);                        
%                     output = ycbcr2rgb( uint8(output) );
%                 else
                    output = uint8(output);
%                 end
            else
                %%% output_RGB (uint8)
                output = uint8(output);
            end

        elseif NetworkMode == 2  % unknown down-sampling on RGB
            LR_input = imlowy;
            Ysize = ceil(size(LR_input,1)); % +3;
            Xsize = ceil(size(LR_input,2)); % +3;
            input = zeros(Ysize,Xsize,scale*scale*3,'single');                       
              for cht=1:3
                startPos = (cht-1)*scale*scale; 
                for ic=1:scale*scale
                    input(:,:,startPos+ic) = single( LR_input(:,:,cht) ); 
                end
              end

            if bPatchMode == 1                       
                ImageSize = Ysize*Xsize;               
                patchmode = 0;
                if ImageSize > 500259  && ImageSize < 750000  %390150
                    patchmode = 1;
                elseif ImageSize >= 750000
                    patchmode = 2;
                end
                output_T = runPatchWNet(net, input, 1, 20, patchmode);
            else
                input = gpuArray(input);
                res    = vl_simplenn(net,input,[],[],1,'conserveMemory',true,'mode','test');                     
                output = input - res(end).x;
                output_T = gather(output);  
            end
            output = zeros(size(label_RGB,1)*scale, size(label_RGB,2)*scale, 3, 'single');
            for nc=1:3
                startPos = (nc-1)*scale*scale+1;
                endPos = startPos + scale*scale-1;
                output(:,:,nc) = vl_nnsubpixelt(output_T(:,:,startPos:endPos), scale, scale);                                 ;
            end                  
            %%% output (single)
            if chanel == 3
                %%% output_RGB (uint8)
                if NetworkMode == 0
                    output = cat(3,output,imlowcb,imlowcr);                        
                    output = ycbcr2rgb( uint8(output) );
                else
                    output = uint8(output);
                end
            else
                %%% output_RGB (uint8)
                output = uint8(output);
            end               

        end
        toc;
        EachTime = toc;
        elapsed_time_Total = elapsed_time_Total + EachTime;                    
       
       %% save results
        if bFileSave == 1
            imwrite(output,fullfile(folderResultCur,[imageName,'.png']));
        end
        if nImgMakingMode <=1                        
            [PSNRs_1(i),SSIMs_1(i)] = compute_psnr_RGB(label_RGB,output,ceil(scale),ceil(scale));
        elseif nImgMakingMode == 2
            HR = imread(fullfile(folderLableCur,filepaths_Lable(i).name)); %filepaths_Low
            LR_out  = imread( fullfile(folderResultCur,[imageName,'.png']) );                        
            PSNRs_1(i) = NTIRE_PeakSNR_imgs(HR, LR_out, ceil(scale));
            SSIMs_1(i) = NTIRE_SSIM_imgs(HR,LR_out, ceil(scale));                        
        end
        disp(['Single Image Super-Resolution22     ',num2str(PSNRs_1(i),'%2.4f'),'dB  ',num2str(SSIMs_1(i),'%2.4f'),'    ',filepaths_Low(i).name]);
end           
disp([mean(PSNRs_1),mean(SSIMs_1)]);
elapsed_time_Total = elapsed_time_Total / length(filepaths_Low);
disp(['Total Time : ',num2str(elapsed_time_Total,'%4.4f'),'sec']);                





