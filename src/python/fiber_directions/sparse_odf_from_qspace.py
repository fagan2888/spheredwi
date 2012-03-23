from __future__ import division
import sys
sys.path.insert(0, '..')

import numpy as np
import scipy as sp
import scipy.special

import matplotlib.pyplot as plt

from sphdif import sphere, coord, plot
from sphdif.kernel import (kernel_matrix, std_kernel, even_kernel,
                           inv_funk_radon_even_kernel, kernel_reconstruct)
from sphdif.linalg import rotation_around_axis
from sphdif.signal_sim import single_tensor, single_tensor_ODF
from sphdif import sph_io

# ========================
# Experiment configuration
# ========================

gamma = np.deg2rad(45)  # Angle separating fibers
D = 150 # Grid density for plots (higher => more dense)

# ====================================
# Load quadrature and set up test data
# ====================================

theta72, phi72, w72 = sphere.quadrature_points(N=72)
theta132, phi132, w132 = sphere.quadrature_points(N=132)
# theta492, phi492, w492 = sphere.quadrature_points(N=492)

# b is tau * |q|^2 in s/mm^2
# If b is too low, the signal does not attenuate enough to measure.
# Too high, the signal to noise ratio increases.

angles = np.array([gamma / 2., -gamma / 2])
R0 = rotation_around_axis([0, 1, 0], angles[0])
R1 = rotation_around_axis([0, 1, 0], angles[1])

# ================
# Q-Space Sampling
# ================

# Note: We sample our signal in Q-space on the low-order quadrature points
# here, but wwe could just as well have used other, random points on the
# sphere.

theta, phi = theta72, phi72
Q = len(theta)
b = 995 + np.random.normal(scale=4, size=Q) # Make up somewhat realistic b-values
xyz = np.column_stack(coord.sph2car(theta, phi))
E = single_tensor(gradients=xyz, bvals=b, S0=1, rotation=R0, SNR=None)
E += single_tensor(gradients=xyz, bvals=b, S0=1, rotation=R1, SNR=None)

# ===========================-=====
# ODF-domain: Sparse reconstruction
# =================================

# Minimising the L1 penalized system
#
# ||Xb - y||_2^2 + lambda ||x||_1 subject to x_i >= 0.
#
# Here, X is reproducing Q-space kernel, y is the Q-space signal vector
# and b are the coefficents.
#
# Note that the L1 penalization of b forces it to be sparse.  This also implies
# that the ODF-domain signal is sparse, since the kernels in A (the reproducing
# kernel matrix in ODF-space) are localised, thus the product Ab is sparse.
# The product Xb is *not* sparse--the kernels in F are donut shaped, and not
# localized.

# See the the low-rank approximation wiki for more detail on these types of
# problems: http://ugcs.caltech.edu/~srbecker/wiki/Main_Page

theta_odf, phi_odf = theta132, phi132
kernel = inv_funk_radon_even_kernel
kernel_N = 16
X = kernel_matrix(theta, phi, theta_odf, phi_odf, kernel=kernel, N=kernel_N)
y = E


from sklearn import linear_model

alpha = 0.0001
L = linear_model.Lasso(alpha=alpha, copy_X=True)

## #L = linear_model.OrthogonalMatchingPursuit(copy_X=True, n_nonzero_coefs=5)

## #a = 0.1 # L1 weight
## #b = 0.8 # L2 weight
## #alpha = a + b
## #rho = a / (a + b)
## #L = linear_model.ElasticNet(alpha=alpha, rho=rho, fit_intercept=False, copy_X=True)

## # # Penalise measurements with low absolute value
## # P = np.diag(1 + np.sqrt(np.abs(s / s.max())))
## # X = P.dot(X)
## # y = P.dot(y)

beta = L.fit(X, y).coef_

sph_io.savez('odf_coeffs', theta=theta_odf, phi=phi_odf, beta=beta,
             separation=gamma)

nnz = np.sum(beta != 0)
print 'Compression: %.2f%%' % ((len(beta) - nnz) / len(beta) * 100)
print 'Non-zero coefficients: %d/%d' % (nnz, len(beta))
print 'Error (Q-space):', np.linalg.norm(X.dot(beta) - y)

## beta[beta < 1e-5] = 0


# ==========================
# ODF-domain: Peak detection
# ==========================

mask = (beta != 0)
print theta_odf[mask], phi_odf[mask]
plot.scatter_3D(theta_odf, phi_odf, color=(0, 0, 1))
plot.scatter_3D(theta_odf[mask], phi_odf[mask], 1 + beta[mask]/beta.max(),
                  transparent=True, color=(1, 0, 0), scale_mode='scalar',
                  scale_factor=0.1, opacity=0.7)

f1_theta, f1_phi, f1_r = coord.car2sph(*R0.dot([1, 0, 0]))
f2_theta, f2_phi, f2_r = coord.car2sph(*R1.dot([1, 0, 0]))
plot.scatter_3D(f1_theta, f1_phi, color=(0, 1, 0), scale_factor=0.15)
plot.scatter_3D(f2_theta, f2_phi, color=(0, 1, 0), scale_factor=0.15)

plot.show()