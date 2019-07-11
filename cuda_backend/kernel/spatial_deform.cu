#include "ops_copy.cuh"

__global__ void device_apply_scale(float* coords, float scale, size_t total_size){
    for(size_t i = blockIdx.x * blockDim.x + threadIdx.x;
        i < total_size;
        i += blockDim.x * gridDim.x){
        coords[i] = coords[i] * scale;
    }
    __syncthreads();
}

__global__ void recenter_2D(float* coords, size_t dim_y, size_t dim_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    if(index < dim_x * dim_y){
        coords[index] += (float)dim_y/2.0;
        coords[index + dim_x*dim_y] += (float)dim_x/2.0;
    }
    __syncthreads();
}

__global__ void recenter_3D(float* coords, size_t dim_z, size_t dim_y, size_t dim_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y * dim_z;
    if(index < total){
        coords[index] += (float)dim_z/2.0;
        coords[index + total] += (float)dim_y/2.0;
        coords[index + 2 * total] += (float)dim_x/2.0;
    }
    __syncthreads();
}

__device__ void exchange(float &a, float &b){
    float temp = a;
    a = b;
    b = temp;
}

__global__ void flip_2D(float* coords, 
                        size_t dim_y, 
                        size_t dim_x,
                        int do_y,
                        int do_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y;
    size_t id_x = index % dim_x;
    size_t id_y = index / dim_x;
    if(index < total){
        if(do_x && id_x < (dim_x / 2)){
            exchange(coords[total + id_y * dim_x + id_x], 
                     coords[total + id_y * dim_x + dim_x-1 - id_x]);
            __syncthreads();
        }
        if(do_y && id_y < (dim_y / 2)){
            exchange(coords[id_y * dim_x + id_x], coords[(dim_y-1 - id_y) * dim_x + id_x]);
            __syncthreads();
        }
    }
}

__global__ void flip_3D(float* coords,
                        size_t dim_z,
                        size_t dim_y, 
                        size_t dim_x,
                        int do_z,
                        int do_y,
                        int do_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y * dim_z;
    size_t total_xy = dim_x * dim_y;
    size_t id_x = index % dim_x;
    size_t id_y = (index / dim_x) % dim_x;
    size_t id_z = index / (dim_x * dim_x);
    if(index < total){
        if(do_x && id_x < (dim_x / 2)){
            exchange(coords[2 * total + id_z * total_xy + id_y * dim_x + id_x], 
                     coords[2 * total + id_z * total_xy + id_y * dim_x + dim_x-1 - id_x]);
            __syncthreads();
        }
        if(do_y && id_y < (dim_y / 2)){
            exchange(coords[total + id_z * total_xy + id_y * dim_x + id_x], 
                     coords[total + id_z * total_xy + (dim_y-1 - id_y) * dim_x + id_x]);
            __syncthreads();
        }
        if(do_z && id_z < (dim_z / 2)){
            exchange(coords[id_z * total_xy + id_y * dim_x + id_x], 
                     coords[(dim_z-1 -id_z) * total_xy + id_y * dim_x + id_x]);
            __syncthreads();
        }
    }
}

__global__ void translate_3D(float* coords,
                            size_t dim_z,
                            size_t dim_y, 
                            size_t dim_x,
                            float seg_z,
                            float seg_y,
                            float seg_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y * dim_z;
    if(index < total){
        coords[index] += seg_z;
        coords[index + total] += seg_y;
        coords[index + total * 2] += seg_x;
        __syncthreads();
    }
}

__global__ void translate_2D(float* coords, 
                            size_t dim_y, 
                            size_t dim_x,
                            float seg_y,
                            float seg_x){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y;
    if(index < total){
        coords[index] += seg_y;
        coords[index + total] += seg_x;
        __syncthreads();
    }
}

__global__ void rotate_2D(float* coords, 
                        size_t dim_y, 
                        size_t dim_x,
                        float cos_angle,
                        float sin_angle){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y;
    float new_y, new_x;
    float old_y = coords[index];
    float old_x = coords[index + total];
    if(index < total){
        new_y = cos_angle * old_y + sin_angle * old_x;
        new_x = -sin_angle * old_y + cos_angle * old_x;
        __syncthreads();
        coords[index] = new_y;
        coords[index + total] = new_x;
        __syncthreads();
    }
}

__global__ void rotate_3D(float* coords, 
                        size_t dim_z,
                        size_t dim_y, 
                        size_t dim_x,
                        float* rot_matrix){
    size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total = dim_x * dim_y * dim_z;
    float new_y = 0, new_x = 0, new_z = 0;
    float old_z = coords[index];
    float old_y = coords[index + total];
    float old_x = coords[index + 2 * total];
    if(index < total){
        new_z = old_z * rot_matrix[0] + old_y * rot_matrix[3] + old_x * rot_matrix[6];
        new_y = old_z * rot_matrix[1] + old_y * rot_matrix[4] + old_x * rot_matrix[7];
        new_x = old_z * rot_matrix[2] + old_y * rot_matrix[5] + old_x * rot_matrix[8];
        __syncthreads();
        coords[index] = new_z;
        coords[index + total] = new_y;
        coords[index + 2 * total] = new_x;
        __syncthreads();
    }
}