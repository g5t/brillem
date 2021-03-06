% brillem -- a MATLAB interface for brille
% Copyright 2020 Greg Tucker
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License

function cellofvecs = get_mapped(obj)
% The python brille mapped functions return either (N,3) or (N,4) arrays of
% (qh,qk,ql) or (qh,qk,ql,en).
if obj.rluNeeded
    QorQE = brillem.p2m(obj.pygrid.rlu);
else
    QorQE = brillem.p2m(obj.pygrid.invA);
end
s2 = size(QorQE,2);
trn = obj.Qtrans(1:s2,1:s2);
if sum(sum(abs(trn - eye(s2))))>0
    for i = 1:size(QorQE,1)
        QorQE(i,:) = permute( trn\permute(QorQE(i,:),[2,1]), [2,1]);
%         QorQE(i,:) = QorQE(i,:)*trn;
    end
end
% arrayfun splits the (N,3 or 4) array into a cell(1,3 or 4) of vectors
cellofvecs = arrayfun(@(i){QorQE(:,i)},1:s2);
end
